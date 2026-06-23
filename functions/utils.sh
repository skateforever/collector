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
    unset kill_check
    unset killremove_check
    unset limit_urls
    unset limiturls_check
    unset output_dir
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
    local patterns_file="${collector_path}/support/secrets-patterns.txt"
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
        } | notify -nc -silent -id "${channel}" > /dev/null 2>&1
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
    local patterns_file="${collector_path}/support/params-patterns.txt"
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
        } | notify -nc -silent -id "${channel}" > /dev/null 2>&1
    fi
}

build_consolidated_urls(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Building consolidated URL list... "
    : > "${tmp_dir}/webapp_consolidated.tmp"
    [[ -s "${report_dir}/webapp_urls.txt" ]] && cat "${report_dir}/webapp_urls.txt" >> "${tmp_dir}/webapp_consolidated.tmp"
    [[ -s "${report_dir}/vhost_urls.txt" ]]  && cat "${report_dir}/vhost_urls.txt"  >> "${tmp_dir}/webapp_consolidated.tmp"
    [[ ! -s "${tmp_dir}/webapp_consolidated.tmp" ]] && { echo "Fail!"; return 0; }
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
    echo "Done! ($(wc -l < "${report_dir}/webapp_consolidated.txt") URLs)"
}

# Internal helper: emits a delimited + optionally truncated section for
# one artifact file into an already-open output file descriptor.
# Args: $1=out_file $2=report_dir $3=relative_path $4=max_lines
_llm_emit_artifact(){
    local out_file="$1" base="$2" rel="$3" max_lines="$4"
    local f="${base}/${rel}"
    [[ ! -s "${f}" ]] && return 0
    local lines head_n tail_n cut line
    echo "===== BEGIN ${rel} =====" >> "${out_file}"
    lines=$(wc -l < "${f}" 2>/dev/null | tr -d ' ')
    if [[ "${lines:-0}" -gt "${max_lines}" ]]; then
        head_n=$(( max_lines / 2 ))
        tail_n=$(( max_lines - head_n ))
        cut=$(( lines - max_lines ))
        while IFS= read -r line; do redact_secrets "${line}"; echo; done < <(head -n "${head_n}" "${f}") >> "${out_file}"
        echo "... [TRUNCATED ${cut} lines] ..." >> "${out_file}"
        while IFS= read -r line; do redact_secrets "${line}"; echo; done < <(tail -n "${tail_n}" "${f}") >> "${out_file}"
    else
        while IFS= read -r line; do redact_secrets "${line}"; echo; done < "${f}" >> "${out_file}"
    fi
    echo "===== END ${rel} =====" >> "${out_file}"
    echo >> "${out_file}"
}

# Generates two focused LLM prompt bundles from the current run:
#
#   llm-local-prompt.txt  — compact bundle for local/small models (quantised
#                           LLaMA-class): only webapp_consolidated.txt and
#                           etc_hosts_file.txt, hard-truncated to fit smaller
#                           context windows. Preamble is minimal and direct.
#
#   llm-claude-prompt.txt — full bundle for cloud-scale models (Claude / GPT-4
#                           class): all high-signal artifacts included, richer
#                           preamble with glossary and operator guidance.
#
# Both files are written to ${report_dir}/.
build_llm_prompt(){
    local max_lines="${llm_prompt_max_lines:-400}"
    local max_lines_local="${llm_prompt_max_lines_local:-100}"
    local target="${domain:-${url_domain:-unknown}}"
    local ts="$(date +"%Y-%m-%d %H:%M:%S %z")"
    local rel f lines size

    [[ ! -d "${report_dir}" ]] && return 0

    # ------------------------------------------------------------------ #
    # llm-local-prompt.txt — webapp_consolidated + etc_hosts only         #
    # ------------------------------------------------------------------ #
    local local_out="${report_dir}/llm-local-prompt.txt"
    : > "${local_out}"
    {
        echo "# COLLECTOR RECON — LOCAL MODEL PROMPT"
        echo "# Target  : ${target}"
        echo "# Date    : ${ts}"
        echo "# Scope   : webapp_consolidated.txt + etc_hosts_file.txt only"
        echo "#"
        echo "# You are an offensive-security assistant. The data below is the"
        echo "# result of an authorized recon run. Use it to answer operator"
        echo "# questions about attack surface, prioritization and next steps."
        echo "# Do not invent hosts, IPs or URLs not present in this data."
        echo "#"
        echo "# webapp_consolidated.txt — all live HTTP(S) URLs (DNS + validated vhosts)"
        echo "# etc_hosts_file.txt      — validated vhosts: ip<TAB>hostname (/etc/hosts format)"
        echo
    } >> "${local_out}"
    _llm_emit_artifact "${local_out}" "${report_dir}" "webapp_consolidated.txt" "${max_lines_local}"
    _llm_emit_artifact "${local_out}" "${report_dir}" "etc_hosts_file.txt"      "${max_lines_local}"
    {
        echo "===== END OF BUNDLE ====="
        echo "# Total artifacts : $(grep -c '^===== BEGIN ' "${local_out}")"
        echo "# Bundle size     : $(wc -c < "${local_out}" | tr -d ' ') bytes"
    } >> "${local_out}"
    echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} LLM local prompt written → ${local_out}"

    # ------------------------------------------------------------------ #
    # llm-claude-prompt.txt — full bundle for large context models         #
    # ------------------------------------------------------------------ #
    local claude_out="${report_dir}/llm-claude-prompt.txt"
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
    : > "${claude_out}"
    {
        echo "########################################################################"
        echo "# COLLECTOR RECON BUNDLE — context for an LLM-driven pentest follow-up"
        echo "########################################################################"
        echo "#"
        echo "# Target domain : ${target}"
        echo "# Generated at  : ${ts}"
        echo "# Source tool   : collector (https://github.com/skateforever/collector)"
        echo "# Report dir    : ${report_dir}"
        echo "#"
        echo "# WHAT THIS FILE IS"
        echo "# -----------------"
        echo "# A consolidated, plain-text dump of the artifacts produced by a"
        echo "# collector recon run against the target above. Each artifact is"
        echo "# enclosed in a delimited section so it can be parsed back out by"
        echo "# string matching:"
        echo "#"
        echo "#     ===== BEGIN <relative/path> ====="
        echo "#     ... raw file content ..."
        echo "#     ===== END <relative/path> ====="
        echo "#"
        echo "# Files larger than ${max_lines} lines are truncated head+tail and the cut"
        echo "# is annotated inline (\"... [TRUNCATED N lines] ...\")."
        echo "# Empty or missing artifacts are listed in the INDEX but their body"
        echo "# is omitted from the bundle."
        echo "#"
        echo "# HOW TO USE THIS FILE (instructions for the receiving LLM)"
        echo "# --------------------------------------------------------"
        echo "# You are an offensive-security assistant. Treat this bundle as the"
        echo "# ground-truth result of a passive + active reconnaissance phase"
        echo "# performed with explicit authorization on the target domain."
        echo "# Do not invent hosts, IPs, URLs, secrets or findings that are not"
        echo "# present in this bundle — operate strictly on the data below plus"
        echo "# any prompts the operator provides next."
        echo "#"
        echo "# Typical follow-up tasks the operator will ask you to perform:"
        echo "#   * Prioritize subdomains / URLs / IPs by likely impact and reach"
        echo "#   * Identify lateral surface (vhosts, internal IPs, AS context)"
        echo "#   * Triage nuclei findings: severity, exploitability, prerequisites"
        echo "#   * Triage webapp_js_secrets.txt and webapp_js_params.txt — propose"
        echo "#     concrete manual tests (parameter names, sinks, sample payloads)"
        echo "#   * Suggest next active steps: auth bypass attempts, SSRF probes,"
        echo "#     IDOR test cases, business-logic abuse, supply-chain checks"
        echo "#   * Draft client-facing write-ups (executive summary + technical"
        echo "#     detail + reproduction steps + remediation)"
        echo "#"
        echo "# CONSTRAINTS"
        echo "# -----------"
        echo "# * Stay within the scope implied by the artifacts (target domain"
        echo "#   and its discovered subdomains / netblocks). Flag — do not act"
        echo "#   on — anything that looks out-of-scope (3rd-party CDNs,"
        echo "#   unrelated ASNs, etc.)."
        echo "# * Treat any token / key / JWT in webapp_js_secrets.txt as a hint,"
        echo "#   not a guaranteed live credential. Recommend validation steps"
        echo "#   instead of assuming compromise."
        echo "# * webapp_js_params.txt categories (SQLi, XSS_*, SSRF_*, XXE,"
        echo "#   CMD_*, PATH_*, DOM_SINK, POSTMSG, CRYPTO_WEAK, PROTO_POLLUTION,"
        echo "#   INTERNAL_HOST) mark code paths worth poking at; they are NOT"
        echo "#   confirmed vulnerabilities. Translate each into a concrete"
        echo "#   manual test plan when the operator asks."
        echo "# * Internal/RFC1918 hosts and metadata IPs (169.254.169.254 etc.)"
        echo "#   surfaced in JS or configs are SSRF-relevant and should be"
        echo "#   highlighted, never reached out to."
        echo "#"
        echo "# ARTIFACT GLOSSARY"
        echo "# -----------------"
        echo "# domains_found / _diff           — union of all subdomain sources"
        echo "# domains_alive                   — subdomains that resolve"
        echo "# domains_without_resolution      — candidates for vhost probing"
        echo "# domains_aliases / _thirdpart    — CNAME/external delegation hints"
        echo "# domains_infrastructure          — A/AAAA/MX/NS landing IPs"
        echo "# domains_internal_ipv4           — RFC1918 / link-local exposure"
        echo "# domains_external_ipv4 / _ipv6   — public IPs the target lives on"
        echo "# zone_transfer                   — AXFR results (rare, high signal)"
        echo "# infra_as / infra_blocks         — AS / BGP / netblock ownership"
        echo "# infra_ipv4 / _ipv4_diff         — consolidated IP universe + delta"
        echo "# webapp_consolidated / _diff     — all live HTTP(S) URLs: DNS + validated vhosts"
        echo "# etc_hosts_file                  — validated vhosts: ip<TAB>hostname (/etc/hosts format)"
        echo "# vhost_subdomains_diff           — delta of validated vhosts vs previous run"
        echo "# email_recon / _diff             — emails harvested per source"
        echo "# robots_urls                     — paths extracted from robots.txt"
        echo "# webapp_js_secrets               — hardcoded keys/tokens/JWTs in JS"
        echo "# webapp_js_params                — param names + DOM/JS sinks worth poking"
        echo "# scan/nmap/nmap_scan             — port + service fingerprints"
        echo "# scan/nuclei/nuclei_scan*        — template-based findings"
        echo "# scan/nuclei/nuclei_web_fuzzing  — fuzzing-template findings"
        echo "# scan/shodan/shodan_scan         — Shodan host facts"
        echo "#"
        echo "########################################################################"
        echo
    } >> "${claude_out}"
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
    } >> "${claude_out}"
    for rel in "${artifacts[@]}"; do
        _llm_emit_artifact "${claude_out}" "${report_dir}" "${rel}" "${max_lines}"
    done
    {
        echo "===== END OF BUNDLE ====="
        echo "# Total artifacts included : $(grep -c '^===== BEGIN ' "${claude_out}")"
        echo "# Bundle size              : $(wc -c < "${claude_out}" | tr -d ' ') bytes"
    } >> "${claude_out}"
    echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} LLM claude prompt written → ${claude_out}"
}

# Ingest the current run's row from ${domain}_history.csv into a local
# SQLite database. The DB lives at ${output_dir}/collector-results-db so
# every target on this host writes to a single canonical store; ingestion
# is idempotent on (domain, run_id) — re-running collector for the same
# run_id replaces the row if any column changed, otherwise it's a no-op.
#
# Designed for low-resource VPSes: SQLite means no daemon, WAL keeps
# readers free while the per-run writer runs, and the schema lives in
# support/collector-sqlite-schema.sqlite so the rule set is editable
# without touching bash.
#
# Called by the orchestrators right after build_llm_prompt.
db_usage(){
    local target="${domain:-${url_domain}}"
    local hist="${output_dir}/${target}/${target}_history.csv"
    local db="${collector_db:-${output_dir}/${collector_db_name:-collector-results-db}}"
    local schema="${collector_db_schema:-support/collector-sqlite-schema.sqlite}"
    [[ "${schema}" != /* ]] && schema="${collector_path:-.}/${schema}"
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
