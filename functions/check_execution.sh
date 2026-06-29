#!/bin/bash
#############################################################
# Verify the execution and parameter dependency             #
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * check_container                                       #
#   * collector_acquire_lock                                #
#   * check_execution                                       #
#   * check_parameter_conflicts                             #
#   * check_parameter_dependency                            #
#                                                           #
#############################################################

check_container(){
    if ! { grep -q "docker\|containerd\|kubepods" /proc/1/cgroup 2>/dev/null || [[ -f "/.dockerenv" ]]; }; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} collector must be executed inside a Docker container."
        exit 1
    fi
}

collector_acquire_lock(){
    local key="$1"
    [[ -z "${key}" ]] && return 0
    if ! command -v flock >/dev/null 2>&1; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} flock not found. collector must run inside the Docker container (util-linux required)."
        exit 1
    fi
    [[ ! -d "${output_dir}/${key}" ]] && mkdir -p "${output_dir}/${key}" 2>/dev/null
    local lockfile="${output_dir}/${key}/.collector.lock"
    exec 9>"${lockfile}" || { echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Cannot create lock file: ${lockfile}"; exit 1; }
    if ! flock -n 9; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Another collector run is already in progress for ${key} (lock: ${lockfile}). Aborting."
        exit 1
    fi
    printf 'pid=%s\nstart=%s\ncmd=%s\n' "$$" "$(date +"%Y-%m-%d %H:%M:%S")" "${collector_command_line}" >&9
}

# Checking if the script has the main parameters needed
check_execution(){
    if [[ -z "${domain_check}" && -z "${domainlist_check}" && -z "${url_check}" ]]; then
        echo -e "You need at least one option \"-d|--domain\", \"-dl|--domain-list\" OR \"-u|--url\" to execute this script!\n"
        usage
    fi

    if [[ -n "${domain_check}" && "${domain_check}" == "yes" ]] && [[ ( -n "${domainlist_check}" && "${domainlist_check}" == "yes" ) && ( -n "${url_check}" && "${url_check}" == "yes" ) ]]; then
        echo -e "You can not use the option -d|--domain with -dl|--domain-list or -u|--url and vice versa.\n"
        usage
    fi

    if [[ -n "${domainlist_check}" && "${domainlist_check}" == "yes" ]] && [[ ( -n "${domain_check}" && "${domain_check}" == "yes" ) && ( -n "${url_check}" && "${url_check}" == "yes" ) ]]; then
        echo -e "You can not use the option -dl|--domain-list with -d|--domain or -u|--url and vice versa.\n"
        usage
    fi

    if [[ -n "${url_check}" && "${url_check}" == "yes" ]] && [[ ( -n "${domain_check}" && "${domain_check}" == "yes" ) && ( -n "${domainlist_check}" && "${domainlist_check}" == "yes" ) ]]; then
        echo -e "You can not use the option -u|--url with -d|--domain or -dl|--domain-list and vice versa.\n"
        usage
    fi

    if [[ -n "${url_check}" && "${url_check}" == "yes" ]] && [[ -n "${url_verify}" ]]; then
        unset user_agent
        user_agent="$(get_user_agent)"
        # Quick reachability check at startup — use the fast profile so an
        # unreachable host doesn't block the whole run for a minute.
        local status_code
        status_code=$(curl "${curl_options_fast[@]}" -H "User-agent: ${user_agent}" -w "%{http_code}" "${url_verify}" > /dev/null)
        if [[ -z ${status_code} || "${status_code}" -eq "000" ]];then
            echo -e "You need specify a valid URL!\n"
            usage
        fi
    fi
}

# Checking the runtime parameter dependency for recon
check_parameter_conflicts(){
    # Check Conflicts
    if [[ -n "${url_check}" && "${url_check}" == "yes" ]]; then
        if [[ "${recon_check}" == "yes" || "${webapp_discovery_check}" == "yes" || "${webapp_enum_check}" == "yes" ]]; then
            echo -e "You are passing parameters that don't work with the -u|--url option.\n"
            usage
        fi
    fi

    if [[ "${excludedomain_check}" == "yes" && "${excludedomainlist_check}" == "yes" ]]; then
        echo "You are trying to use same domain exclusion options, just pick one."
        usage
    fi

    if [[ "${limiturls_check}" == "yes" && "${url_check}" == "yes" ]]; then
        echo -e "You can only use this -l|--limit-urls option with -d|--domain!\n"
        usage
    fi

    if [[ "${subdomainbrute_check}" == "yes" && "${url_check}" == "yes" ]]; then
        echo -e "You can only use this -s|--subdomain-brute option with -d|--domain!\n"
        usage
    fi
}

check_parameter_dependency(){
    if [[ "${domain_check}" == "yes" || "${domainlist_check}" == "yes" ]]; then
        # Basic Execution Check
        if [[ ! -d "${report_dir}" && "${recon_check}" != "yes" ]]; then
            echo -e "You are trying to perform recon, but don't have a structure and are using a different parameter than -r|--recon with domain options."
            echo -e "You need to perform at least a basic run to get the subdomain discovered and continue the rest of the activities.\n"
            usage
        fi

        if [[ "${webapp_crawler_check}" == "yes" || "${webapp_discovery_check}" == "yes" || "${webapp_enum_check}" == "yes" || "${webapp_scan_check}" == "yes" ]]; then
            if [[ ! -d "${report_dir}" && "${recon_check}" != "yes" ]]; then
                echo -e "You are trying to perform web application discovery where the basic recognition structure does not yet exist, run the collector again with the -r|--recon option.\n"
                usage
            fi
        fi

        # Web Application Crawler Check
        if [[ "${webapp_crawler_check}" == "yes" && ( ! -s "${report_dir}/webapp_consolidated.txt" && "${webapp_discovery_check}" != "yes" ) ]] ; then
            echo -e "You are trying to run web application crawler without having previously web application discovery, use the -wd|--webapp-discovery option and run again.\n"
            usage
        fi

        # Web Application Discovery Check
        if [[ "${webapp_discovery_check}" == "yes" && ( ! -s "${report_dir}/domains_alive.txt" && "${recon_check}" != "yes" ) ]] ; then
            echo -e "You are trying to run web application enumeration without having previously web application discovery, use the -r|--recon option and run again.\n"
            usage
        fi

        if [[ "${webapp_discovery_check}" == "yes" && ${#webapp_port_detect[@]} -eq 0 ]]; then
            echo -e "You are trying to find out which web applications are active, but forgot to specify which ports to test."
            echo -e "Choose one of the options -wld|--webapp-long-detection or -wsd|--webapp-short-detection and run again.\n"
            usage
        fi

        if [[ "${webapp_discovery_check}" != "yes" && ${#webapp_port_detect[@]} -gt 0 ]]; then
            echo -e "You trying to execute collector to perform web application discovery without setting -wd|--webapp-discovery option.\n"
            usage
        fi

        # Web Application Enumeration Check
        if [[ "${webapp_enum_check}" == "yes" && ( ! -s "${report_dir}/webapp_consolidated.txt" && "${webapp_discovery_check}" != "yes" ) ]] ; then
            echo -e "You are trying to run web application enumeration without having previously web application discovery, use the -wd|--webapp-discovery option and run again.\n"
            usage
        fi

        if [[ "${webapp_enum_check}" == "yes" && ${#webapp_wordlists[@]} -eq 0 ]]; then
            echo -e "Please, ${yellow}make sure${reset} you have at least one wordlist to web directory and file discovery!\n"
            usage
        fi

        # Web Application Scan Check
        if [[ "${webapp_scan_check}" == "yes" && ( ! -s "${report_dir}/webapp_consolidated.txt" && "${webapp_discovery_check}" != "yes" ) ]] ; then
            echo -e "You are trying to run web application scan without having previously web application discovery, use the -wd|--webapp-discovery option and run again.\n"
            usage
        fi
    fi

    # Full Execution Check

    # URL
    if [[ -n "${url_check}" && "${url_check}" == "yes" ]]; then
        if [[ -n "${url_verify}" ]]; then
            if [[ "${args_count}" -gt 4 ]]; then
                echo -e "You are trying to pass a number of parameters beyond what is necessary for this collector reconnaissance option \"${yellow}-u|--url${reset}\".\n"
                usage
            fi
        fi
        if [[ -n "${url_verify}" ]]; then
            if [[ "${args_count}" -gt 4 ]] && [[ ${#webapp_wordlists[@]} -eq 0 ]]; then
                echo -e "Maybe you forget the -ww|--webapp-wordlist option to use with reconnaissance option \"${yellow}-u|--url${reset}\".\n"
                usage
            fi
        fi
    fi
}
