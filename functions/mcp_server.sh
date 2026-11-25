#!/bin/bash
#############################################################
#                                                           #
# collector-mcp.py lifecycle.                               #
#                                                           #
# Same two-launch-mode/one-shared-pidfile shape as           #
# functions/web_report.sh — see that file's own header for   #
# the full rationale, which applies here unchanged:          #
#                                                           #
#   * background — spawned at the tail of a recon run so    #
#                  an MCP client can query results the       #
#                  moment the run finishes.                  #
#   * foreground — spawned by `collector --mcp-up` alone,   #
#                  exec-replacing the collector process so   #
#                  Ctrl-C reaches collector-mcp.py cleanly.  #
#                                                           #
# One pidfile/logfile under support/mcp/run/ (sibling to     #
# support/mcp/collector-mcp.py itself) — a shared identity   #
# so --shutdown can stop EITHER launch mode, same as         #
# it does for web-report.                                     #
#                                                           #
# Only the streamable-http transport is supported here —    #
# stdio is a per-MCP-client subprocess with no network port  #
# and no long-lived identity of its own to track via a       #
# pidfile, so it's out of scope for --mcp-up/--shutdown      #
# entirely (an MCP client still launches it directly, per    #
# support/mcp/MCP.md, completely independent of this file).  #
#                                                           #
# Exposes:                                                  #
#   * mcp_server_run_dir            (path helper)            #
#   * mcp_server_pidfile            (path helper)            #
#   * mcp_server_logfile            (path helper)            #
#   * run_mcp_server                (mode-parameterized)      #
#   * start_mcp_server              (background wrapper)      #
#   * start_mcp_server_foreground   (foreground wrapper)      #
#   * stop_mcp_server               (SIGTERM→SIGKILL)         #
#                                                           #
#############################################################

# mcp_server_run_dir — support/mcp/run, sibling to collector-mcp.py itself.
# mkdir -p defensively; also tracked in git via a .gitkeep (same pattern as
# support/web-report/run) so a fresh checkout/image already has it.
mcp_server_run_dir(){
    local mcp_dir="${collector_path:-.}/support/mcp"
    echo "${mcp_dir}/run"
}

# mcp_server_pidfile / mcp_server_logfile — path resolvers shared by every
# start/stop path (background AND foreground alike), same reasoning as
# web_report_pidfile/web_report_logfile.
mcp_server_pidfile(){
    echo "${mcp_server_pidfile_path:-$(mcp_server_run_dir)/${mcp_server_pidfile_name:-collector-mcp.pid}}"
}
mcp_server_logfile(){
    echo "${mcp_server_logfile_path:-$(mcp_server_run_dir)/${mcp_server_logfile_name:-collector-mcp.log}}"
}

# _mcp_server_pid_is_live — is this PID actually OUR collector-mcp.py
# process, not merely a live PID? Same /proc/<pid>/cmdline disambiguation
# as _web_report_pid_is_live, and for the exact same reason: a pidfile
# written by a foreground run (where collector-mcp.py exec'd into PID 1)
# reads back as "pid 1, alive" in the NEXT container too, where PID 1 is
# `collector` itself — without this check, start_mcp_server would
# false-positive "already running" and stop_mcp_server would SIGTERM
# collector's own PID 1.
_mcp_server_pid_is_live(){
    local _pid="$1"
    [[ -n "${_pid}" ]] || return 1
    kill -0 "${_pid}" 2>/dev/null || return 1
    local _cmdline
    _cmdline="$(tr '\0' ' ' < "/proc/${_pid}/cmdline" 2>/dev/null)"
    [[ "${_cmdline}" == *collector-mcp.py* ]]
}

# run_mcp_server — single implementation behind start_mcp_server (called at
# the tail of a recon run, backgrounded) and start_mcp_server_foreground
# (called by `collector --mcp-up` alone, exec-replaces this shell). Mirrors
# run_web_report's structure (functions/web_report.sh) point for point.
#
# Mode-dependent behavior is fenced by "$1", same meaning as run_web_report:
#   background  — nohup + &, returns after confirming the child is alive.
#                 A failed preflight is a soft skip (return 0) so a recon
#                 run isn't aborted by a missing/misconfigured MCP server.
#   foreground  — exec so collector-mcp.py takes over PID $$. Preflight
#                 failures are hard errors (return 1) since the whole
#                 point of the invocation is to serve MCP clients.
run_mcp_server(){
    local mode="$1"
    local tag
    case "${mode}" in
        background) tag="start_mcp_server" ;;
        foreground) tag="start_mcp_server_foreground" ;;
        *) echo "run_mcp_server: unknown mode '${mode}'" >&2; return 2 ;;
    esac

    # Same reasoning as run_web_report's report_up_check gate: background
    # mode only ever fires when the operator explicitly asked for it via
    # -mu|--mcp-up. Foreground mode needs no such gate — it's only ever
    # reached via the --mcp-up-alone dispatch in collector, where
    # mcp_up_check is already implied.
    if [[ "${mode}" == "background" && "${mcp_up_check:-}" != "yes" ]]; then
        return 0
    fi

    # streamable-http is the only transport with a network port and a
    # long-lived process identity to track via a pidfile — stdio is a
    # per-client subprocess an MCP client spawns itself (see support/mcp/
    # MCP.md), there is nothing here for --mcp-up to start or --shutdown
    # to stop. Reject clearly up front rather than let collector-mcp.py
    # start on stdio, immediately block reading an empty stdin, and look
    # like a hang with no explanation.
    if [[ "${collector_mcp_transport:-stdio}" != "streamable-http" ]]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} ${tag}: collector_mcp_transport is '${collector_mcp_transport:-stdio}', not 'streamable-http'."
        echo -e "  Set ${yellow}collector_mcp_transport=\"streamable-http\"${reset} in conf.d/operation.conf before using -mu|--mcp-up — stdio has no network port for a background/foreground service to bind."
        [[ "${mode}" == "foreground" ]] && return 1 || return 0
    fi

    local mcp_script="${collector_path:-.}/support/mcp/collector-mcp.py"
    # Same bind-vs-announce split as run_web_report's bind_address/
    # host_address: bind_address is the CONTAINER-internal address
    # collector-mcp.py's own FastMCP(host=...) actually binds to (must be
    # 0.0.0.0 for -mu|--mcp-up's published port to reach it — a 127.0.0.1
    # bind here is unreachable through `docker run -p` no matter how
    # correctly the port is published, same confirmed failure mode as
    # web_report_container_address's own comment). host/port are what the
    # OPERATOR types into their client — never bound directly, only
    # printed and handed to collector-docker's -p mapping.
    local bind_address="${collector_mcp_container_address:-127.0.0.1}"
    local port="${collector_mcp_port:-8010}"
    local host="${collector_mcp_host:-127.0.0.1}"
    mkdir -p "$(mcp_server_run_dir)" 2>/dev/null
    local pidfile logfile
    pidfile="$(mcp_server_pidfile)"
    logfile="$(mcp_server_logfile)"

    if [[ ! -s "${mcp_script}" ]]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} ${tag}: ${mcp_script} not found."
        [[ "${mode}" == "foreground" ]] && return 1 || return 0
    fi

    # ─── already-running detection ─────────────────────────────────────
    # One shared pidfile for both launch modes (see file header) — a live
    # process behind it blocks starting a new instance in ANY mode, both
    # would race on the same TCP port.
    if [[ -s "${pidfile}" ]]; then
        local check_pid
        check_pid="$(cat "${pidfile}" 2>/dev/null)"
        if ! _mcp_server_pid_is_live "${check_pid}"; then
            # Stale pidfile from a previous run (or a previous CONTAINER —
            # see _mcp_server_pid_is_live) — clean and move on.
            rm -f "${pidfile}"
        else
            echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} ${tag}: already running (pid ${check_pid}) — access it at http://${host}:${port}"
            if [[ "${mode}" == "foreground" ]]; then
                echo -e "  stop it with ${yellow}collector --shutdown${reset} (or ${yellow}collector-docker --shutdown${reset}) before starting a new one."
                return 1
            fi
            return 0
        fi
    fi

    # Even without a matching pidfile, the TCP port may already be taken —
    # same rationale and same tool-availability fallback as run_web_report's
    # own port-busy check.
    if command -v ss >/dev/null 2>&1; then
        if ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${port}$"; then
            echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} ${tag}: port ${port} is already bound by another process."
            if [[ "${mode}" == "foreground" ]]; then
                echo -e "  free the port or set ${yellow}collector_mcp_port${reset} in conf.d/operation.conf to a different value."
                return 1
            fi
            return 0
        fi
    fi

    if ! command -v python3 >/dev/null 2>&1; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} ${tag}: python3 not found."
        [[ "${mode}" == "foreground" ]] && return 1 || return 0
    fi

    export COLLECTOR_MCP_TRANSPORT="streamable-http"
    # COLLECTOR_MCP_CONTAINER_ADDRESS, not COLLECTOR_MCP_HOST — the bind
    # address collector-mcp.py's own FastMCP(host=...) actually binds to
    # has to be bind_address (the CONTAINER-internal one, see its own
    # local above), never the operator-facing `host`. Exporting `host`
    # here instead was the exact bug that made -mu|--mcp-up unreachable
    # through collector-docker's -p mapping (uvicorn only ever bound
    # 127.0.0.1 inside the container, confirmed via `docker exec ...
    # curl` succeeding while curl from outside got "Empty reply from
    # server" — same failure mode web_report_container_address's own
    # comment documents).
    export COLLECTOR_MCP_CONTAINER_ADDRESS="${bind_address}"
    export COLLECTOR_MCP_PORT="${port}"
    # Not strictly required — collector-mcp.py already resolves both from
    # conf.d/operation.conf on its own when it can read that file — but
    # exported anyway for the same belt-and-suspenders reason run_web_report
    # exports COLLECTOR_DB/COLLECTOR_OUTPUT_DIR for app.py.
    export COLLECTOR_DB="${collector_db:-${collector_path}/${web_report_dir:-support/web-report}/db/${collector_db_name:-collector-results}}"
    export COLLECTOR_OUTPUT_DIR="${output_dir}"

    if [[ "${mode}" == "foreground" ]]; then
        # Same tee-before-exec trick as run_web_report's foreground path —
        # see its own comment for why this has to happen before the
        # "is up" announcement and why it survives the exec below.
        exec > >(tee -a "${logfile}") 2>&1
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} The collector MCP server is up — access it at http://${host}:${port} (Ctrl-C or --shutdown to stop)"
        echo "$$" > "${pidfile}.tmp" && mv "${pidfile}.tmp" "${pidfile}"
        exec python3 "${mcp_script}"
        # exec should have replaced us. If we reach here, exec itself failed.
        rm -f "${pidfile}"
        return 1
    fi

    # ─── background path ───────────────────────────────────────────────
    (
        nohup python3 "${mcp_script}" >> "${logfile}" 2>&1 &
        echo $! > "${pidfile}"
    )

    sleep 1
    if [[ -s "${pidfile}" ]] && _mcp_server_pid_is_live "$(cat "${pidfile}")"; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} The collector MCP server is up — access it at http://${host}:${port}"
    else
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} ${tag}: failed to start (see ${logfile})"
        rm -f "${pidfile}"
        return 1
    fi
}

# Thin wrappers preserve the same call-site shape as web_report.sh's own
# start_web_report/start_web_report_foreground.
start_mcp_server(){ run_mcp_server background; }
start_mcp_server_foreground(){ run_mcp_server foreground; }

# stop_mcp_server — counterpart of BOTH start_mcp_server and
# start_mcp_server_foreground, now that they share one pidfile. Identical
# SIGTERM→wait 5s→SIGKILL escalation as stop_web_report — see that
# function's own comments for the full rationale (container PID-namespace
# caveats included). Returns 0 on success or when there was nothing to
# stop, 1 only if the kill escalation failed.
stop_mcp_server(){
    local pidfile
    pidfile="$(mcp_server_pidfile)"

    if [[ ! -s "${pidfile}" ]]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} stop_mcp_server: no pidfile at ${pidfile} — nothing to stop."
        return 0
    fi

    local pid
    pid="$(cat "${pidfile}" 2>/dev/null)"
    if ! _mcp_server_pid_is_live "${pid}"; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} stop_mcp_server: stale pidfile (pid ${pid:-?} not alive, or not our MCP server — see this container's own namespace), removing."
        rm -f "${pidfile}"
        return 0
    fi

    echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} stop_mcp_server: sending SIGTERM to collector-mcp.py (pid ${pid})"
    kill -TERM "${pid}" 2>/dev/null

    local waited=0
    while [[ "${waited}" -lt 5 ]]; do
        if ! kill -0 "${pid}" 2>/dev/null; then
            rm -f "${pidfile}"
            echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} stop_mcp_server: stopped."
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
    done

    # Didn't exit within 5s — force it.
    echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} stop_mcp_server: SIGTERM ignored after 5s, escalating to SIGKILL."
    if kill -KILL "${pid}" 2>/dev/null; then
        rm -f "${pidfile}"
        return 0
    fi
    echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} stop_mcp_server: SIGKILL failed for pid ${pid}."
    return 1
}
