#!/bin/bash
#############################################################
#                                                           #
# app-report dashboard lifecycle.                           #
#                                                           #
# The dashboard (Flask+HTMX under gunicorn) is read-only    #
# and runs in two modes:                                    #
#                                                           #
#   * background — spawned at the tail of a recon run so    #
#                  the operator can browse results the      #
#                  moment the run finishes.                 #
#   * foreground — spawned by `collector --report-only`,    #
#                  exec-replacing the collector process so  #
#                  Ctrl-C reaches gunicorn cleanly.         #
#                                                           #
# One implementation (run_app_report) handles both; the     #
# public wrappers below are the historical entry points.    #
#                                                           #
# Exposes:                                                  #
#   * app_report_foreground_pidfile   (path helper)         #
#   * run_app_report                  (mode-parameterized)  #
#   * start_app_report                (background wrapper)  #
#   * start_app_report_foreground     (foreground wrapper)  #
#   * stop_app_report_foreground      (SIGTERM→SIGKILL)     #
#                                                           #
# Depends on start_cloudflare_tunnel from                   #
# functions/cloudflare_tunnel.sh (optional add-on).         #
#                                                           #
#############################################################

# app_report_foreground_pidfile — path resolver shared by the foreground
# start and stop paths. Kept as a helper so both agree on where the file
# lives. The .fg suffix differentiates the foreground pidfile from the
# background one written by mode=background below, so a recon run (which
# leaves a background dashboard) and a --report-only session can coexist
# without clobbering each other.
app_report_foreground_pidfile(){
    local base="${app_report_pidfile_name:-.app-report.pid}"
    echo "${app_report_pidfile:-${output_dir}/${base%.pid}.fg.pid}"
}

# run_app_report — single implementation behind start_app_report (called
# at the tail of a recon run, backgrounded) and start_app_report_foreground
# (called by `collector --report-only`, exec-replaces this shell).
#
# Everything the two variants used to duplicate lives here:
#   * enablement gate (app_report_enabled)
#   * resolution of app_dir / host / port / db
#   * "already running?" pidfile check with stale-file cleanup
#   * env-var exports consumed by app.py
#   * gunicorn preferred, python3 app.py fallback
#
# Mode-dependent behavior is fenced by "$1":
#   background  — nohup + &, redirects logs to file, optional cloudflare
#                 tunnel, returns after confirming the child is alive.
#                 A missing app_dir / DB is a soft skip (return 0) so a
#                 recon run isn't aborted by a missing UI.
#   foreground  — exec so gunicorn takes over PID $$, logs to stdout, no
#                 tunnel, no return-on-success (exec never returns).
#                 Preflight failures are hard errors (return 1) since the
#                 whole point of the invocation is to serve the UI.
run_app_report(){
    local mode="$1"
    local tag                    # log-line prefix and pidfile lookup key
    case "${mode}" in
        background) tag="start_app_report" ;;
        foreground) tag="start_app_report_foreground" ;;
        *) echo "run_app_report: unknown mode '${mode}'" >&2; return 2 ;;
    esac

    if [[ "${app_report_enabled:-yes}" != "yes" ]]; then
        # Background path used to silently return; foreground path now
        # tells the operator why nothing happened — either way, we bail.
        if [[ "${mode}" == "foreground" ]]; then
            echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} ${tag}: app_report_enabled=no in collector.cfg, refusing to start."
            return 1
        fi
        return 0
    fi

    local app_dir="${app_report_dir:-app-report}"
    [[ "${app_dir}" != /* ]] && app_dir="${collector_path:-.}/${app_dir}"
    local host="${app_report_host:-127.0.0.1}"
    local port="${app_report_port:-8000}"
    local db="${collector_db:-${output_dir}/${collector_db_name:-collector-results-db}}"
    local pidfile logfile
    if [[ "${mode}" == "foreground" ]]; then
        pidfile="$(app_report_foreground_pidfile)"
        logfile=""   # foreground writes to stdout/stderr, no file
    else
        pidfile="${app_report_pidfile:-${output_dir}/${app_report_pidfile_name:-.app-report.pid}}"
        logfile="${app_report_logfile:-${output_dir}/${app_report_logfile_name:-.app-report.log}}"
    fi

    if [[ ! -d "${app_dir}" ]]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} ${tag}: ${app_dir} not found."
        [[ "${mode}" == "foreground" ]] && return 1 || return 0
    fi
    # DB preflight was missing in the old background path; adding it here
    # so both modes fail cleanly instead of letting Flask return 503 later.
    if [[ ! -f "${db}" ]]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} ${tag}: collector-results-db not found at ${db}."
        if [[ "${mode}" == "foreground" ]]; then
            echo -e "  no scan has completed on this outputs dir, so there is nothing to render."
            return 1
        fi
        # Background: still soft-skip — the recon that called us will
        # write the DB on the next db_usage call, and a re-invocation
        # will find it.
        return 0
    fi

    # ─── already-running detection ─────────────────────────────────────
    # Two pidfiles can exist on the same outputs/ volume:
    #   background: .app-report.pid   (written by start_app_report from
    #               inside a recon run)
    #   foreground: .app-report.fg.pid (written by --report-only)
    # A live process behind EITHER pidfile blocks starting a new instance
    # in ANY mode — both would race on the same TCP port. Hence we check
    # both, not just the pidfile of the current mode.
    local bg_pidfile fg_pidfile
    bg_pidfile="${app_report_pidfile:-${output_dir}/${app_report_pidfile_name:-.app-report.pid}}"
    fg_pidfile="$(app_report_foreground_pidfile)"

    local check_file check_pid check_mode
    for check_file in "${bg_pidfile}" "${fg_pidfile}"; do
        [[ -s "${check_file}" ]] || continue
        check_pid="$(cat "${check_file}" 2>/dev/null)"
        if [[ -z "${check_pid}" ]] || ! kill -0 "${check_pid}" 2>/dev/null; then
            # Stale pidfile from a previous run — clean and move on.
            rm -f "${check_file}"
            continue
        fi
        [[ "${check_file}" == "${fg_pidfile}" ]] && check_mode="foreground" || check_mode="background"
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} ${tag}: already running (pid ${check_pid}, ${check_mode} mode) at http://${host}:${port}"
        if [[ "${mode}" == "foreground" ]]; then
            echo -e "  stop it with ${yellow}collector --report-stop${reset} (or ${yellow}collector-docker --report-stop${reset}) before starting a new one."
            return 1
        fi
        return 0
    done

    # Even without a matching pidfile, the TCP port may already be taken
    # (someone started gunicorn by hand, or a sibling container is
    # publishing to it). Refuse rather than let the launcher fail with an
    # opaque 'address already in use'. `ss` is present in the collector
    # image; when unavailable we silently skip this check and let gunicorn
    # surface the error itself.
    if command -v ss >/dev/null 2>&1; then
        if ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${port}$"; then
            echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} ${tag}: port ${port} is already bound by another process."
            if [[ "${mode}" == "foreground" ]]; then
                echo -e "  free the port or set ${yellow}app_report_port${reset} in collector.cfg to a different value."
                return 1
            fi
            return 0
        fi
    fi

    # Launcher selection is shared. Missing both binaries is a soft skip
    # in background (the recon carries on without a UI) but a hard error
    # in foreground (nothing else to do).
    local launcher=""
    if command -v gunicorn >/dev/null 2>&1; then
        launcher="gunicorn"
    elif command -v python3 >/dev/null 2>&1; then
        launcher="python3"
    else
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} ${tag}: neither gunicorn nor python3 found."
        [[ "${mode}" == "foreground" ]] && return 1 || return 0
    fi

    export COLLECTOR_DB="${db}"
    export COLLECTOR_OUTPUT_DIR="${output_dir}"
    export APP_REPORT_HOST="${host}"
    export APP_REPORT_PORT="${port}"

    if [[ "${mode}" == "foreground" ]]; then
        cd "${app_dir}" || return 1
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} ${tag}: serving at http://${host}:${port} (Ctrl-C or --report-stop to stop)"
        # Record OUR pid before exec — after exec, $$ is inherited by
        # gunicorn (same PID, different program), so --report-stop still
        # targets the right process. Written to a temp path + rename so a
        # concurrent --report-stop never sees a half-written file.
        echo "$$" > "${pidfile}.tmp" && mv "${pidfile}.tmp" "${pidfile}"
        if [[ "${launcher}" == "gunicorn" ]]; then
            exec gunicorn --workers 1 --bind "${host}:${port}" \
                --access-logfile - --error-logfile - app:app
        else
            exec python3 app.py
        fi
        # exec should have replaced us. If we reach here, exec itself failed.
        rm -f "${pidfile}"
        return 1
    fi

    # ─── background path ───────────────────────────────────────────────
    (
        cd "${app_dir}" || exit 1
        if [[ "${launcher}" == "gunicorn" ]]; then
            nohup gunicorn --workers 1 --bind "${host}:${port}" \
                --access-logfile - --error-logfile - app:app \
                >> "${logfile}" 2>&1 &
        else
            nohup python3 app.py >> "${logfile}" 2>&1 &
        fi
        echo $! > "${pidfile}"
    )

    sleep 1
    if [[ -s "${pidfile}" ]] && kill -0 "$(cat "${pidfile}")" 2>/dev/null; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} ${tag}: serving at http://${host}:${port} (pid $(cat "${pidfile}"), log ${logfile})"
    else
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} ${tag}: failed to start (see ${logfile})"
        rm -f "${pidfile}"
        return 1
    fi

    # Optional Cloudflare quick-tunnel — gives the gunicorn we just started
    # an ephemeral https://*.trycloudflare.com URL so the dashboard is
    # reachable without exposing the VPS IP/port. Opt-in via collector.cfg.
    # Only meaningful for the background path (foreground is one-shot).
    if [[ "${cloudflare_tunnel:-no}" == "yes" ]]; then
        start_cloudflare_tunnel "${port}"
    fi
}

# Thin wrappers preserve the historical call-sites (domains_recon.sh,
# url_recon.sh, collector) — no other file had to change for the refactor.
start_app_report(){ run_app_report background; }
start_app_report_foreground(){ run_app_report foreground; }

# stop_app_report_foreground — counterpart of start_app_report_foreground.
# Signals the gunicorn master recorded in the pidfile with SIGTERM (which
# gunicorn handles gracefully), waits up to 5 seconds, then escalates to
# SIGKILL. Also cleans up stale pidfiles. Returns 0 on success or when
# there was nothing to stop, 1 only if the kill escalation failed.
#
# Note on containers: when the dashboard was started via `collector-docker
# --report-only`, the gunicorn PID lives inside that container's PID
# namespace, not the host's. `collector-docker --report-stop` handles that
# case by running `docker stop` from the host; this function is the
# in-container half, invoked when the operator hits `collector
# --report-stop` inside the same container (or runs the collector
# natively on the host).
stop_app_report_foreground(){
    local pidfile
    pidfile="$(app_report_foreground_pidfile)"

    if [[ ! -s "${pidfile}" ]]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} stop_app_report_foreground: no pidfile at ${pidfile} — nothing to stop."
        return 0
    fi

    local pid
    pid="$(cat "${pidfile}" 2>/dev/null)"
    if [[ -z "${pid}" ]] || ! kill -0 "${pid}" 2>/dev/null; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} stop_app_report_foreground: stale pidfile (pid ${pid:-?} not alive), removing."
        rm -f "${pidfile}"
        return 0
    fi

    echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} stop_app_report_foreground: sending SIGTERM to gunicorn (pid ${pid})"
    kill -TERM "${pid}" 2>/dev/null

    local waited=0
    while [[ "${waited}" -lt 5 ]]; do
        if ! kill -0 "${pid}" 2>/dev/null; then
            rm -f "${pidfile}"
            echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} stop_app_report_foreground: stopped."
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
    done

    # Didn't exit within 5s — force it.
    echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} stop_app_report_foreground: SIGTERM ignored after 5s, escalating to SIGKILL."
    if kill -KILL "${pid}" 2>/dev/null; then
        rm -f "${pidfile}"
        return 0
    fi
    echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} stop_app_report_foreground: SIGKILL failed for pid ${pid}."
    return 1
}
