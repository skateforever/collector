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

# scan_js_secrets and scan_js_params moved to scans/js_scans.sh.

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
