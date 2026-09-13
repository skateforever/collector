#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * banner                                                #
#   * reset_vars                                            #
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
    # output_dir intentionally NOT unset here: it's set by conf.d/operation.conf at
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
    unset dry_run_check
    unset vhost_check_check
    unset args_count
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
    local proc_count

    while true; do
        # Obtém contagem de processos com tratamento seguro
        proc_count=$(pgrep -cf "${pattern}" 2>/dev/null)
        local pgrep_result=$?

        # Se pgrep falhou (não encontrou ou erro)
        if [[ ${pgrep_result} -eq 1 ]]; then
            # Exit code 1 = No processes matched (esperado)
            proc_count=0
        elif [[ ${pgrep_result} -ne 0 ]]; then
            # Erro real (permissão, sintaxe, etc) - falhar abertamente
            echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} ERROR: pgrep failed (exit code: ${pgrep_result}) for pattern '${pattern}'. Possible permission issue."
            return 1
        fi

        # Log detalhado para debugging
        [[ ${elapsed} -eq 0 ]] && echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Waiting for '${pattern}' to drop below ${max_procs} procs (currently: ${proc_count})"

        # Verificar condição de limite
        if [[ ${proc_count} -lt ${max_procs} ]]; then
            break
        fi

        sleep 5
        ((elapsed += 5))
        if [[ "${elapsed}" -ge "${timeout_secs}" ]]; then
            echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} WARNING: wait timed out after ${timeout_secs}s for '${pattern}' (${proc_count} procs still running), killing stale processes"
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

# count_lines — safe `wc -l` for files that may not exist yet (e.g. a scan
# type that wasn't enabled this run). A plain `wc -l < "$file" 2>/dev/null`
# doesn't actually suppress a missing file: redirections apply left to
# right, so the failing `<` open error prints to the terminal BEFORE
# `2>/dev/null` takes effect. Checking existence first avoids that failing
# redirect altogether.
count_lines(){
    [[ -s "$1" ]] && wc -l < "$1" || echo 0
}

run_summary(){
    local summary_target="${1:-${domain}}"
    local n_found n_alive n_ips n_webapps n_findings
    n_found="$(count_lines "${report_dir}/domains_found.txt")"
    n_alive="$(count_lines "${report_dir}/domains_alive.txt")"
    n_ips="$(count_lines "${report_dir}/infra_ipv4.txt")"
    n_webapps="$(count_lines "${report_dir}/webapp_consolidated.txt")"
    n_findings="$(count_lines "${nuclei_scan_file}")"

    echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Run Summary:"
    echo -e "  Subdomains found:  ${n_found}"
    echo -e "  Subdomains alive:  ${n_alive}"
    echo -e "  Unique IPs:        ${n_ips}"
    echo -e "  Web apps:          ${n_webapps}"
    echo -e "  Nuclei findings:   ${n_findings}"
    echo -e "  Duration:          $((SECONDS / 60))m $((SECONDS % 60))s"
    printf "Run complete: %s | %s subdomains | %s alive | %s webapps | %s findings | %dm%ds" \
        "${summary_target}" "${n_found}" "${n_alive}" "${n_webapps}" "${n_findings}" \
        "$((SECONDS / 60))" "$((SECONDS % 60))" \
        | notify "${notify_options[@]}" -id "${notify_recon_channel}" > /dev/null 2>&1
}

# Safe wrapper for dig with timeout
dig_safe(){
    # Usage: dig_safe <record_type> <hostname>
    # Example: dig_safe A example.com
    # Example: dig_safe CNAME www.example.com
    local record_type="${1:-A}"
    local hostname="$2"

    [[ -z "${hostname}" ]] && return 1

    # +time=2: 2-second timeout
    # +tries=1: single attempt (no retry)
    # +short: clean output format
    dig +short +time=2 +tries=1 "${record_type}" "${hostname}" 2>/dev/null
}
