#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * banner                                                #
#   * reset_vars                                            #
#   * build_consolidated_urls                               #
#                                                           #
#############################################################

# Always print the banner
banner(){
echo -e "                                 __ __             __
                    ____ ____   / // /___   ____ _/ /_ ____   ____
                   / __// __ \ / // // _ \ / __//_ __// __ \ / __/ 
                  / /__/ /_/ // // // ___// /__ / /_ / /_/ // /  
                  \___/\____//_//_/ \___/ \___/ \__/ \____//_/   

                                                     by skate4ever
"
}

# Always reset the variables to run the collector
reset_vars(){
    unset directory_structure
    unset domain_check
    unset domainlist_check
    unset excluded_domains
    unset excludedomain_check
    unset excludedomain_list
    unset excludedomainlist_check
    unset limit_urls
    unset limiturls_check
    # output_dir intentionally NOT unset here: it's set by collector.cfg at
    # source-time (currently pinned to /opt/collector/outputs by the
    # Dockerfile) and the collector runs exclusively inside Docker. The
    # CLI flag -o/--output that previously could override it was removed,
    # so the cfg value is now the single source of truth.
    unset use_proxy
    unset recon_check
    unset dns_wordlists
    unset subdomainbrute_check
    unset url_check
    unset url_verify
    unset url_domain
    unset webapp_crawler_check
    unset webapp_discovery_check
    unset webapp_enum_check
    unset webapp_scan_check
    unset webapp_port_detect
    unset webapp_wordlists
}

# Resolve a runtime asset path (user-agents list, regex patterns, LLM
# prompt header, SQLite schema). If the input is absolute, it is returned
# as-is — letting the operator point at a host-mounted override. If it
# is relative, it is prefixed with ${collector_path} so the default cfg
# values resolve against the collector install dir regardless of the
# caller's cwd.
#
# Used by:
#   get_user_agent       — ${collector_user_agents}
#   scan_js_secrets      — ${collector_secrets_patterns}
#   scan_js_params       — ${collector_params_patterns}
#   build_llm_prompt     — ${collector_llm_header}
#   db_usage             — ${collector_db_schema}
resolve_asset_path(){
    local _p="$1"
    [[ -z "${_p}" ]] && return 1
    if [[ "${_p}" == /* ]]; then
        printf '%s' "${_p}"
    else
        printf '%s/%s' "${collector_path:-.}" "${_p}"
    fi
}

# Build a notify_pc_args array that holds `-pc <path>` if the configured
# provider config exists, or stays empty otherwise. Every `notify ...`
# call expands "${notify_pc_args[@]}" inline; an empty array expands to
# zero arguments, so the call gracefully falls back to notify's default
# search path (\$HOME/.config/notify/provider-config.yaml) when no host
# config is bind-mounted into the container.
#
# Called once at boot from collector main, after collector.cfg is sourced
# and resolve_asset_path() is available.
init_notify_pc_args(){
    notify_pc_args=()
    if [[ -n "${collector_notify_config}" && -s "${collector_notify_config}" ]]; then
        notify_pc_args=(-pc "${collector_notify_config}")
    fi
}

# Replace any occurrence of the configured API keys with a redacted marker.
# Use before writing curl command lines or response bodies to log files,
# so that sharing the log for debugging doesn't leak credentials.
redact_secrets(){
    local _line="$1"
    local _var _val
    for _var in builtwith_api_key censys_api_id censys_api_secret \
                dnsdumpster_api_key hunterio_api lampyre_api_key \
                riskiq_api_key riskiq_api_secret securitytrails_api_key \
                shodan_apikey snov_api_token virustotal_api_key \
                whoisxmlapi_api_key; do
        _val="${!_var}"
        if [[ -n "${_val}" ]]; then
            _line="${_line//${_val}/***REDACTED***}"
        fi
    done
    printf '%s' "${_line}"
}

# Scan downloaded JavaScript files for likely API keys, tokens, secrets and
# other credentials. Designed to run after crawler_js, so the input is already
# scoped to the target's own code (the crawler filters by domain before
# downloading). Each hit is written as one line:
#
#     <label>:<file>:<line>:<match>
#
# Args:
#   $1 - directory to scan recursively (default: ${webapp_js_dir})
#   $2 - output file              (default: ${report_dir}/webapp_js_secrets.txt)
scan_js_secrets(){
    local scan_dir="${1:-${webapp_js_dir}}"
    local out_file="${2:-${report_dir}/webapp_js_secrets.txt}"
    local patterns_file="$(resolve_asset_path "${collector_secrets_patterns}")"
    local label regex hits line total
    local channel="${notify_high_channel:-${notify_recon_channel}}"

    [[ ! -d "${scan_dir}" ]] && return 0
    if [[ ! -s "${patterns_file}" ]]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} JS secrets: pattern file missing → ${patterns_file}"
        return 1
    fi

    : > "${out_file}"
    {
        echo "# JS secret-scan report for ${domain}"
        echo "# scan_dir: ${scan_dir}"
        echo "# patterns: ${patterns_file}"
        echo "# date: $(date +"%Y-%m-%d %H:%M:%S")"
        echo "# format: <label>:<file>:<line>:<match>"
        echo
    } >> "${out_file}"

    total=0
    while IFS='|' read -r label regex; do
        # Skip blanks and comments. Require both fields.
        [[ -z "${label}" || "${label}" =~ ^[[:space:]]*# || -z "${regex}" ]] && continue
        hits="$(grep -rEHnIoi --include='*.js' "${regex}" "${scan_dir}" 2>/dev/null)"
        [[ -z "${hits}" ]] && continue
        while IFS= read -r line; do
            # Strip our own configured API keys from the output so the report
            # never echoes back the operator's own credentials.
            line="$(redact_secrets "${line}")"
            printf '%s:%s\n' "${label}" "${line}" >> "${out_file}"
            total=$((total+1))
        done <<< "${hits}"
    done < "${patterns_file}"

    if [[ "${total}" -gt 0 ]]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} JS secrets: ${total} candidate(s) flagged → ${out_file}"
        {
            echo "JS secret candidates for ${domain}: ${total}"
            echo "Report: ${out_file}"
            echo
            grep -v '^#' "${out_file}" | grep -v '^$' | head -n 30
            [[ "${total}" -gt 30 ]] && echo "... ($((total - 30)) more)"
        } | notify "${notify_pc_args[@]}" -nc -silent -id "${channel}" > /dev/null 2>&1
    fi
}

# Scan downloaded JavaScript files for parameter names and DOM/JS sinks that
# commonly mark injection-prone code paths. The goal isn't to prove a bug —
# it's to give the operator a starting list of "places worth poking at"
# during manual testing.
#
# For each pattern category (SQLi, XSS, SSRF, XXE, CMD, OPEN_REDIRECT, PATH,
# DOM_SINK, EVAL_SINK, POSTMSG, CRYPTO_WEAK) the function emits hits in:
#
#     <category>:<file>:<line>:<match>
#
# Categories are intentionally broad: a hit means "this name or sink appears
# in the code", not "this is exploitable". Triage in the manual phase.
#
# Args:
#   $1 - directory to scan recursively (default: ${webapp_js_dir})
#   $2 - output file              (default: ${report_dir}/webapp_js_params.txt)
scan_js_params(){
    local scan_dir="${1:-${webapp_js_dir}}"
    local out_file="${2:-${report_dir}/webapp_js_params.txt}"
    local patterns_file="$(resolve_asset_path "${collector_params_patterns}")"
    local label regex hits line total
    local channel="${notify_recon_channel}"

    [[ ! -d "${scan_dir}" ]] && return 0
    if [[ ! -s "${patterns_file}" ]]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} JS sinks: pattern file missing → ${patterns_file}"
        return 1
    fi

    : > "${out_file}"
    {
        echo "# JS param/sink scan report for ${domain}"
        echo "# scan_dir: ${scan_dir}"
        echo "# patterns: ${patterns_file}"
        echo "# date: $(date +"%Y-%m-%d %H:%M:%S")"
        echo "# format: <category>:<file>:<line>:<match>"
        echo "# NOTE: a hit means \"worth a manual look\", not \"vulnerable\"."
        echo
    } >> "${out_file}"

    total=0
    while IFS='|' read -r label regex; do
        [[ -z "${label}" || "${label}" =~ ^[[:space:]]*# || -z "${regex}" ]] && continue
        hits="$(grep -rEHnIoi --include='*.js' "${regex}" "${scan_dir}" 2>/dev/null)"
        [[ -z "${hits}" ]] && continue
        while IFS= read -r line; do
            line="$(redact_secrets "${line}")"
            printf '%s:%s\n' "${label}" "${line}" >> "${out_file}"
            total=$((total+1))
        done <<< "${hits}"
    done < "${patterns_file}"

    if [[ "${total}" -gt 0 ]]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} JS sinks: ${total} candidate(s) flagged → ${out_file}"
        {
            echo "JS injection-sink candidates for ${domain}: ${total}"
            echo "Report: ${out_file}"
            echo
            echo "Per-category counts:"
            grep -v '^#' "${out_file}" | grep -v '^$' | awk -F: '{print $1}' | sort | uniq -c | sort -rn
            echo
            echo "Top hits:"
            grep -v '^#' "${out_file}" | grep -v '^$' | head -n 30
            [[ "${total}" -gt 30 ]] && echo "... ($((total - 30)) more)"
        } | notify "${notify_pc_args[@]}" -nc -silent -id "${channel}" > /dev/null 2>&1
    fi
}

cleanup_etc_hosts(){
    sed -i '/# collector-vhosts-start/,/# collector-vhosts-end/d' /etc/hosts 2>/dev/null
}

build_consolidated_urls(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Building consolidated URL list... "
    : > "${tmp_dir}/webapp_consolidated.tmp"
    [[ -s "${report_dir}/webapp_urls.txt" ]] && cat "${report_dir}/webapp_urls.txt" >> "${tmp_dir}/webapp_consolidated.tmp"
    [[ -s "${report_dir}/vhost_urls.txt" ]]  && cat "${report_dir}/vhost_urls.txt"  >> "${tmp_dir}/webapp_consolidated.tmp"
    [[ ! -s "${tmp_dir}/webapp_consolidated.tmp" ]] && { echo "Fail!"; return 0; }
    if [[ -s "${report_dir}/etc_hosts_file.txt" ]]; then
        cleanup_etc_hosts
        if [[ -w "/etc/hosts" ]]; then
            { echo "# collector-vhosts-start"; awk '{print $1"\t"$2}' "${report_dir}/etc_hosts_file.txt"; echo "# collector-vhosts-end"; } >> /etc/hosts
            trap 'cleanup_etc_hosts' EXIT
        else
            echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Warning: /etc/hosts is not writable — vhost entries will not resolve via getent. Run as root or grant write access." >> "${log_execution_file}"
            echo "Warning: /etc/hosts not writable; vhost entries skipped." | notify "${notify_pc_args[@]}" -nc -silent -id "${notify_recon_channel}" > /dev/null 2>&1
        fi
    fi
    sort -u "${tmp_dir}/webapp_consolidated.tmp" > "${tmp_dir}/webapp_consolidated_sorted.tmp"
    : > "${tmp_dir}/webapp_consolidated_validated.tmp"
    while IFS= read -r url; do
        host="$(echo "${url}" | sed -E 's|^https?://([^/:]+).*|\1|')"
        if getent hosts "${host}" > /dev/null 2>&1; then
            echo "${url}" >> "${tmp_dir}/webapp_consolidated_validated.tmp"
            echo "consolidated [ok]:      ${url}" >> "${log_execution_file}"
        else
            echo "consolidated [skipped]: ${url} (no resolution)" >> "${log_execution_file}"
        fi
    done < "${tmp_dir}/webapp_consolidated_sorted.tmp"
    sort -u -o "${report_dir}/webapp_consolidated.txt" "${tmp_dir}/webapp_consolidated_validated.tmp"
    mv "${report_dir}/webapp_urls.txt" "${tmp_dir}/webapp_urls.old" 2>/dev/null
    mv "${report_dir}/vhost_urls.txt"  "${tmp_dir}/vhost_urls.old"  2>/dev/null
    [[ ! -s "${report_dir}/webapp_consolidated.txt" ]] && { echo "Fail! (no resolvable hosts)"; return 0; }
    echo "Done! ($(wc -l < "${report_dir}/webapp_consolidated.txt") URLs)"
}

# Internal helper: emits a delimited + optionally truncated section for
# one artifact file into an already-open output file descriptor.
# Args: $1=out_file $2=report_dir $3=relative_path $4=max_lines
_llm_emit_artifact(){
    local out_file="$1" base="$2" rel="$3"
    local f="${base}/${rel}"
    [[ ! -s "${f}" ]] && return 0
    local line
    echo "===== BEGIN ${rel} =====" >> "${out_file}"
    while IFS= read -r line; do redact_secrets "${line}"; echo; done < "${f}" >> "${out_file}"
    echo "===== END ${rel} =====" >> "${out_file}"
    echo >> "${out_file}"
}

# Generates a single LLM prompt bundle from the current run containing all
# artifacts produced by collector. Written to ${report_dir}/llm-prompt.txt.
# Header is read from ${collector_path}/support/runtime/prompts/llm-header.txt with
# __TARGET__, __TS__ and __REPORT_DIR__ replaced at generation time.
build_llm_prompt(){
    local target="${domain:-${url_domain:-unknown}}"
    local ts="$(date +"%Y-%m-%d %H:%M:%S %z")"
    local rel f lines size
    local header_file="$(resolve_asset_path "${collector_llm_header}")"
    local out="${report_dir}/llm-prompt.txt"

    [[ ! -d "${report_dir}" ]] && return 0
    [[ ! -s "${header_file}" ]] && { echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} build_llm_prompt: header template missing → ${header_file}"; return 1; }

    local -a artifacts=(
        "domains_found.txt"
        "domains_diff.txt"
        "domains_alive.txt"
        "domains_without_resolution.txt"
        "domains_excluded.txt"
        "domains_aliases.txt"
        "domains_thirdpart.txt"
        "domains_infrastructure.txt"
        "domains_internal_ipv4.txt"
        "domains_external_ipv4.txt"
        "domains_external_ipv6.txt"
        "zone_transfer.txt"
        "infra_as.txt"
        "infra_ipv4.txt"
        "infra_ipv4_diff.txt"
        "infra_ipv6.txt"
        "infra_blocks.txt"
        "webapp_consolidated.txt"
        "webapp_consolidated_diff.txt"
        "etc_hosts_file.txt"
        "vhost_subdomains_diff.txt"
        "email_recon.txt"
        "email_recon_diff.txt"
        "robots_urls.txt"
        "webapp_js_secrets.txt"
        "webapp_js_params.txt"
        "scan/nmap/nmap_scan.txt"
        "scan/nuclei/nuclei_scan.result"
        "scan/nuclei/nuclei_scan_diff.txt"
        "scan/nuclei/nuclei_web_fuzzing.result"
        "scan/shodan/shodan_scan.txt"
    )

    : > "${out}"
    sed \
        -e "s|__TARGET__|${target}|g" \
        -e "s|__TS__|${ts}|g" \
        -e "s|__REPORT_DIR__|${report_dir}|g" \
        "${header_file}" >> "${out}"
    echo >> "${out}"
    {
        echo "===== INDEX ====="
        for rel in "${artifacts[@]}"; do
            f="${report_dir}/${rel}"
            if [[ -s "${f}" ]]; then
                lines=$(wc -l < "${f}" 2>/dev/null | tr -d ' ')
                size=$(wc -c < "${f}" 2>/dev/null | tr -d ' ')
                printf '  [present] %-44s lines=%s size=%s\n' "${rel}" "${lines}" "${size}"
            else
                printf '  [empty]   %s\n' "${rel}"
            fi
        done
        echo "===== END INDEX ====="
        echo
    } >> "${out}"
    for rel in "${artifacts[@]}"; do
        _llm_emit_artifact "${out}" "${report_dir}" "${rel}"
    done
    {
        echo "===== END OF BUNDLE ====="
        echo "# Total artifacts included : $(grep -c '^===== BEGIN ' "${out}")"
        echo "# Bundle size              : $(wc -c < "${out}" | tr -d ' ') bytes"
    } >> "${out}"
    echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} LLM prompt written → ${out}"
}

# Ingest the current run's row from ${domain}_history.csv into a local
# SQLite database. The DB lives at ${output_dir}/collector-results-db so
# every target on this host writes to a single canonical store; ingestion
# is idempotent on (domain, run_id) — re-running collector for the same
# run_id replaces the row if any column changed, otherwise it's a no-op.
#
# Designed for low-resource VPSes: SQLite means no daemon, WAL keeps
# readers free while the per-run writer runs, and the schema lives in
# support/runtime/schema/collector-results.sql so the rule set is editable
# without touching bash.
#
# Called by the orchestrators right after build_llm_prompt.
db_usage(){
    local target="${domain:-${url_domain}}"
    local hist="${output_dir}/${target}/${target}_history.csv"
    local db="${collector_db:-${output_dir}/${collector_db_name:-collector-results-db}}"
    # Default kept here as a safety net if the cfg ever drops the variable;
    # resolve_asset_path() handles the absolute-vs-relative prefix logic.
    local schema="$(resolve_asset_path "${collector_db_schema:-support/runtime/schema/collector-results.sql}")"
    local fresh=0

    if ! command -v sqlite3 >/dev/null 2>&1; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} db_usage: sqlite3 binary not found, skipping ingestion."
        return 0
    fi

    if [[ -z "${target}" ]]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} db_usage: no target in scope, skipping."
        return 0
    fi

    if [[ ! -s "${hist}" ]]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} db_usage: history CSV missing → ${hist}"
        return 0
    fi

    if [[ ! -s "${schema}" ]]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} db_usage: schema file missing → ${schema}"
        return 1
    fi

    # Bootstrap the DB the first time we see this host.
    if [[ ! -s "${db}" ]]; then
        fresh=1
        if ! sqlite3 "${db}" < "${schema}" 2>> "${log_execution_file}"; then
            echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} db_usage: failed to create ${db} from schema."
            return 1
        fi
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} db_usage: created ${db} (schema: ${schema})"
    else
        # Apply schema as IF-NOT-EXISTS — covers upgrades that add columns,
        # indexes or views without touching existing data.
        sqlite3 "${db}" < "${schema}" 2>> "${log_execution_file}"
    fi

    # Pull this run's row out of the CSV. The latest row in the file is
    # always the run we just finished — record_history appends.
    local run_id
    run_id="$(basename "${recon_dir}")"

    # Use awk to extract the row matching this run_id (no trailing
    # newline issues, no header row). awk also handles the case where
    # the CSV header order changes — we feed columns positionally, so
    # the schema/CSV column order must match. Guard against that with a
    # header-shape check.
    local header expected
    header="$(head -n 1 "${hist}")"
    expected="domain,run_id,run_date,started_at,finished_at,mode,subdomains,subdomains_alive,subdomains_added,ips,ips_added,webapp_consolidated,webapp_consolidated_added,vhosts_strong,vhosts_added,emails,emails_added,js_secrets,js_params,findings_info,findings_low,findings_medium,findings_high,findings_critical,report_dir,llm_prompt_path,status"
    if [[ "${header}" != "${expected}" ]]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} db_usage: history CSV header drift, refusing to ingest."
        echo "  expected: ${expected}" >> "${log_execution_file}"
        echo "  got:      ${header}"   >> "${log_execution_file}"
        return 1
    fi

    local row
    row="$(awk -F',' -v r="${run_id}" 'NR>1 && $2==r {line=$0} END{print line}' "${hist}")"
    if [[ -z "${row}" ]]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} db_usage: no row for ${run_id} in ${hist}."
        return 1
    fi

    # Hand the single row to sqlite via a temp CSV stage table. Using
    # INSERT OR REPLACE on (domain, run_id) is the idempotency guarantee:
    # a re-run of the same run_id only writes when the row content
    # actually differs; SQLite's REPLACE rewrites the row in place. The
    # outer WHERE EXISTS makes the no-op cheap when nothing changed.
    local stage
    stage="$(mktemp -t collector-stage.XXXXXX.csv)" || return 1
    {
        echo "${expected}"
        echo "${row}"
    } > "${stage}"

    sqlite3 "${db}" 2>> "${log_execution_file}" <<SQL
.bail on
BEGIN IMMEDIATE;
INSERT OR IGNORE INTO targets(domain) VALUES ('${target}');

-- Stage table mirrors the CSV payload columns ONLY (28 cols). Cloning
-- recon_runs verbatim used to pull in `ingested_at` too, leaving the
-- column NULL after .import — the subsequent `SELECT s.*, datetime('now')`
-- then produced one too many values for the destination table. Define
-- the schema explicitly so the import shape always matches the CSV.
CREATE TEMP TABLE recon_runs_stage (
    domain              TEXT,
    run_id              TEXT,
    run_date            TEXT,
    started_at          TEXT,
    finished_at         TEXT,
    mode                TEXT,
    subdomains          INTEGER,
    subdomains_alive    INTEGER,
    subdomains_added    INTEGER,
    ips                 INTEGER,
    ips_added           INTEGER,
    webapp_consolidated       INTEGER,
    webapp_consolidated_added INTEGER,
    vhosts_strong       INTEGER,
    vhosts_added        INTEGER,
    emails              INTEGER,
    emails_added        INTEGER,
    js_secrets          INTEGER,
    js_params           INTEGER,
    findings_info       INTEGER,
    findings_low        INTEGER,
    findings_medium     INTEGER,
    findings_high       INTEGER,
    findings_critical   INTEGER,
    report_dir          TEXT,
    llm_prompt_path     TEXT,
    status              TEXT
);
.mode csv
.import --skip 1 '${stage}' recon_runs_stage

-- Only write if the incoming row differs from what's already stored.
-- Compare every payload column; ignore ingested_at (server-side default).
-- Columns are listed explicitly on the destination side so a future
-- schema change to recon_runs can't silently misalign the SELECT.
INSERT OR REPLACE INTO recon_runs (
    domain, run_id, run_date, started_at, finished_at, mode,
    subdomains, subdomains_alive, subdomains_added,
    ips, ips_added,
    webapp_consolidated, webapp_consolidated_added,
    vhosts_strong, vhosts_added,
    emails, emails_added,
    js_secrets, js_params,
    findings_info, findings_low, findings_medium, findings_high, findings_critical,
    report_dir, llm_prompt_path, status,
    ingested_at
)
SELECT s.*, datetime('now') AS ingested_at
FROM recon_runs_stage s
LEFT JOIN recon_runs r
       ON r.domain = s.domain AND r.run_id = s.run_id
WHERE r.run_id IS NULL
   OR r.run_date          IS NOT s.run_date
   OR r.started_at        IS NOT s.started_at
   OR r.finished_at       IS NOT s.finished_at
   OR r.mode              IS NOT s.mode
   OR r.subdomains        IS NOT s.subdomains
   OR r.subdomains_alive  IS NOT s.subdomains_alive
   OR r.subdomains_added  IS NOT s.subdomains_added
   OR r.ips               IS NOT s.ips
   OR r.ips_added         IS NOT s.ips_added
   OR r.webapp_consolidated       IS NOT s.webapp_consolidated
   OR r.webapp_consolidated_added IS NOT s.webapp_consolidated_added
   OR r.vhosts_strong     IS NOT s.vhosts_strong
   OR r.vhosts_added      IS NOT s.vhosts_added
   OR r.emails            IS NOT s.emails
   OR r.emails_added      IS NOT s.emails_added
   OR r.js_secrets        IS NOT s.js_secrets
   OR r.js_params         IS NOT s.js_params
   OR r.findings_info     IS NOT s.findings_info
   OR r.findings_low      IS NOT s.findings_low
   OR r.findings_medium   IS NOT s.findings_medium
   OR r.findings_high     IS NOT s.findings_high
   OR r.findings_critical IS NOT s.findings_critical
   OR r.report_dir        IS NOT s.report_dir
   OR r.llm_prompt_path   IS NOT s.llm_prompt_path
   OR r.status            IS NOT s.status;

DROP TABLE recon_runs_stage;
COMMIT;
SQL
    local rc=$?
    rm -f "${stage}"

    if [[ "${rc}" -ne 0 ]]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} db_usage: ingestion failed (see ${log_execution_file})."
        return 1
    fi

    if [[ "${fresh}" -eq 1 ]]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} db_usage: ${target} ${run_id} ingested into fresh DB → ${db}"
    else
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} db_usage: ${target} ${run_id} synced → ${db}"
    fi
}

# Launch the read-only Flask+HTMX UI in the background. PID-file based:
# if a previous recon run already started it, this is a no-op so multiple
# concurrent runs don't fight over the socket.
start_app_report(){
    if [[ "${app_report_enabled:-yes}" != "yes" ]]; then
        return 0
    fi
    local app_dir="${app_report_dir:-app-report}"
    [[ "${app_dir}" != /* ]] && app_dir="${collector_path:-.}/${app_dir}"
    local host="${app_report_host:-127.0.0.1}"
    local port="${app_report_port:-8000}"
    local pidfile="${app_report_pidfile:-${output_dir}/${app_report_pidfile_name:-.app-report.pid}}"
    local logfile="${app_report_logfile:-${output_dir}/${app_report_logfile_name:-.app-report.log}}"
    local db="${collector_db:-${output_dir}/${collector_db_name:-collector-results-db}}"

    if [[ ! -d "${app_dir}" ]]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} start_app_report: ${app_dir} not found, skipping."
        return 0
    fi

    # Already running? Trust the PID file iff the process is alive.
    if [[ -s "${pidfile}" ]]; then
        local existing
        existing="$(cat "${pidfile}" 2>/dev/null)"
        if [[ -n "${existing}" ]] && kill -0 "${existing}" 2>/dev/null; then
            echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} start_app_report: already running (pid ${existing}) at http://${host}:${port}"
            return 0
        fi
        rm -f "${pidfile}"
    fi

    # Need either gunicorn (preferred) or python3 fallback for dev.
    local launcher=""
    if command -v gunicorn >/dev/null 2>&1; then
        launcher="gunicorn"
    elif command -v python3 >/dev/null 2>&1; then
        launcher="python3"
    else
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} start_app_report: neither gunicorn nor python3 found, skipping."
        return 0
    fi

    (
        cd "${app_dir}" || exit 1
        export COLLECTOR_DB="${db}"
        export COLLECTOR_OUTPUT_DIR="${output_dir}"
        export APP_REPORT_HOST="${host}"
        export APP_REPORT_PORT="${port}"
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
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} start_app_report: serving at http://${host}:${port} (pid $(cat "${pidfile}"), log ${logfile})"
    else
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} start_app_report: failed to start (see ${logfile})"
        rm -f "${pidfile}"
        return 1
    fi

    # Optional Cloudflare quick-tunnel — gives the gunicorn we just started
    # an ephemeral https://*.trycloudflare.com URL so the dashboard is
    # reachable without exposing the VPS IP/port. Opt-in via collector.cfg.
    if [[ "${cloudflare_tunnel:-no}" == "yes" ]]; then
        start_cloudflare_tunnel "${port}"
    fi
}

# Launch a cloudflared quick-tunnel pointing at the local app-report
# port. Same PID-file discipline as start_app_report so concurrent recon
# runs share a single tunnel. The trycloudflare URL is parsed back out of
# cloudflared's log and echoed for the operator. Failure is non-fatal:
# the run finishes whether or not the tunnel comes up — the local
# gunicorn is still serving.
start_cloudflare_tunnel(){
    local local_port="$1"
    local cf_pidfile="${cloudflare_tunnel_pidfile:-${output_dir}/${cloudflare_tunnel_pidfile_name:-.cloudflared.pid}}"
    local cf_logfile="${cloudflare_tunnel_logfile:-${output_dir}/${cloudflare_tunnel_logfile_name:-.cloudflared.log}}"
    local cf_timeout="${cloudflare_tunnel_url_timeout:-30}"

    if ! command -v cloudflared >/dev/null 2>&1; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} start_cloudflare_tunnel: cloudflared binary not found in PATH, skipping (install it or set cloudflare_tunnel=\"no\")."
        return 0
    fi

    # Already running? Trust the PID file iff the process is alive. We
    # also try to recover the public URL from the existing logfile so the
    # operator sees it again on every run instead of having to grep.
    if [[ -s "${cf_pidfile}" ]]; then
        local cf_existing
        cf_existing="$(cat "${cf_pidfile}" 2>/dev/null)"
        if [[ -n "${cf_existing}" ]] && kill -0 "${cf_existing}" 2>/dev/null; then
            local cf_url_existing
            cf_url_existing="$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "${cf_logfile}" 2>/dev/null | tail -n1)"
            if [[ -n "${cf_url_existing}" ]]; then
                echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} start_cloudflare_tunnel: already running (pid ${cf_existing}) → ${cf_url_existing}"
            else
                echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} start_cloudflare_tunnel: already running (pid ${cf_existing}, log ${cf_logfile})"
            fi
            return 0
        fi
        rm -f "${cf_pidfile}"
    fi

    # Truncate the logfile so the URL we grep for below is from THIS
    # tunnel run, not a previous one.
    : > "${cf_logfile}"

    (
        nohup cloudflared tunnel --no-autoupdate --url "http://localhost:${local_port}" \
            >> "${cf_logfile}" 2>&1 &
        echo $! > "${cf_pidfile}"
    )

    # Give cloudflared up to ${cf_timeout} seconds to print the
    # trycloudflare URL. The URL appears in stderr (which we redirected
    # into the logfile) within a couple of seconds in practice, so 30s is
    # generous.
    local cf_url=""
    local waited=0
    while [[ "${waited}" -lt "${cf_timeout}" ]]; do
        if [[ -s "${cf_pidfile}" ]] && ! kill -0 "$(cat "${cf_pidfile}")" 2>/dev/null; then
            echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} start_cloudflare_tunnel: cloudflared exited before publishing a URL (see ${cf_logfile})"
            rm -f "${cf_pidfile}"
            return 1
        fi
        cf_url="$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "${cf_logfile}" 2>/dev/null | tail -n1)"
        [[ -n "${cf_url}" ]] && break
        sleep 1
        waited=$((waited + 1))
    done

    if [[ -n "${cf_url}" ]]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} start_cloudflare_tunnel: serving at ${cf_url} (pid $(cat "${cf_pidfile}"), log ${cf_logfile})"
    else
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} start_cloudflare_tunnel: timed out waiting for trycloudflare URL after ${cf_timeout}s (see ${cf_logfile}); tunnel may still be starting."
    fi
}
