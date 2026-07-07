#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * banner                                                #
#   * reset_vars                                            #
#   * redact_secrets                                        #
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

# cleanup_etc_hosts and build_consolidated_urls moved to functions/files.sh.

# llm_emit_artifact and build_llm_prompt moved to functions/llm_prompt.sh.

# db_usage moved to functions/db_usage.sh.


# app-report lifecycle moved to functions/app_report.sh.
# start_cloudflare_tunnel moved to functions/cloudflare_tunnel.sh.

wait_with_timeout(){
    local pattern="$1"
    local max_procs="${2:-1}"
    local timeout_secs="${3:-3600}"
    local elapsed=0
    while [[ "$(pgrep -acf "${pattern}" 2>/dev/null || echo 0)" -ge "${max_procs}" ]]; do
        sleep 5
        ((elapsed += 5))
        if [[ "${elapsed}" -ge "${timeout_secs}" ]]; then
            echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} WARNING: wait timed out after ${timeout_secs}s for '${pattern}', killing stale processes"
            pkill -9 -f "${pattern}" 2>/dev/null
            sleep 2
            break
        fi
    done
}

validate_ipv4_file(){
    local file="$1"
    if [[ ! -s "${file}" ]]; then return 0; fi
    local total valid invalid
    total=$(wc -l < "${file}")
    valid=$(awk '{print $NF}' "${file}" | grep -cE '^([0-9]{1,3}\.){3}[0-9]{1,3}$' || echo 0)
    invalid=$((total - valid))
    if [[ "${invalid}" -gt 0 ]]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} WARNING: ${file} has ${invalid}/${total} invalid entries. Cleaning..."
        awk '{if ($NF ~ /^([0-9]{1,3}\.){3}[0-9]{1,3}$/) print}' "${file}" > "${file}.clean" && mv "${file}.clean" "${file}"
    fi
}

# Escape dots in a domain name for use in regex patterns.
escape_domain_re(){
    printf '%s' "${1//./\\.}"
}
