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
    unset report_only_check
    unset report_stop_check
}

# Replace any occurrence of the configured API keys with a redacted marker.
# Use before writing curl command lines or response bodies to log files,
# so that sharing the log for debugging doesn't leak credentials.
redact_secrets(){
    local line="$1"
    local var val
    for var in builtwith_api_key censys_api_id censys_api_secret \
                dnsdumpster_api_key hunterio_api lampyre_api_key \
                riskiq_api_key riskiq_api_secret securitytrails_api_key \
                shodan_apikey snov_api_token virustotal_api_key \
                whoisxmlapi_api_key; do
        val="${!var}"
        if [[ -n "${val}" ]]; then
            line="${line//${val}/***REDACTED***}"
        fi
    done
    printf '%s' "${line}"
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
    local patterns_file="${collector_secrets_patterns}"
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
        } | notify "${notify_options[@]}" -id "${channel}" > /dev/null 2>&1
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
    local patterns_file="${collector_params_patterns}"
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
        } | notify "${notify_options[@]}" -id "${channel}" > /dev/null 2>&1
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
            echo "Warning: /etc/hosts not writable; vhost entries skipped." | notify "${notify_options[@]}" -id "${notify_recon_channel}" > /dev/null 2>&1
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

# llm_emit_artifact and build_llm_prompt moved to functions/llm_prompt.sh.

# db_usage moved to functions/db_usage.sh.


# app-report lifecycle moved to functions/app_report.sh.
# start_cloudflare_tunnel moved to functions/cloudflare_tunnel.sh.
