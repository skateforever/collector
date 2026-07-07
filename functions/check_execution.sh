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
# Parameter dependency tree:                                #
#                                                           #
#   -wd|--webapp-discovery                                  #
#       ├─ requires: -wld OR -wsd (port detection mode)     #
#       ├─ requires: -r|--recon (for domains_alive.txt)     #
#       └─ enables:                                         #
#           ├─ -wc|--webapp-crawler                         #
#           ├─ -we|--webapp-enum (also needs -ww)           #
#           ├─ -ws|--webapp-scan                            #
#           └─ -vv|--vhost-validation                       #
#                                                           #
#   -we|--webapp-enum                                       #
#       ├─ requires: -wd|--webapp-discovery                 #
#       └─ requires: -ww|--webapp-wordlists                 #
#                                                           #
#   -wld|--webapp-long-detection                            #
#   -wsd|--webapp-short-detection                           #
#       └─ requires: -wd|--webapp-discovery                 #
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

    local mode_count=0
    [[ "${domain_check}" == "yes" ]] && ((mode_count += 1))
    [[ "${domainlist_check}" == "yes" ]] && ((mode_count += 1))
    [[ "${url_check}" == "yes" ]] && ((mode_count += 1))

    if [[ "${mode_count}" -gt 1 ]]; then
        echo -e "You can only use ONE of -d|--domain, -dl|--domain-list, or -u|--url at a time.\n"
        usage
    fi

    if [[ -n "${url_check}" && "${url_check}" == "yes" ]] && [[ -n "${url_verify}" ]]; then
        unset user_agent
        user_agent="$(get_user_agent)"
        # Quick reachability check at startup — use the fast profile so an
        # unreachable host doesn't block the whole run for a minute.
        local status_code
        status_code=$(curl "${curl_options_fast[@]}" -H "User-agent: ${user_agent}" -w "%{http_code}" "${url_verify}" -o /dev/null 2>/dev/null)
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

    if [[ "${vhost_validation_check}" == "yes" && "${webapp_discovery_check}" != "yes" ]]; then
        echo -e "The -vv|--vhost-validation option requires -wd|--webapp-discovery to work.\n"
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
            echo -e "The -wc|--webapp-crawler option requires -wd|--webapp-discovery to discover web applications first."
            echo -e "Run with -wd|--webapp-discovery (and -wsd or -wld) to generate webapp_consolidated.txt, then run crawler.\n"
            usage
        fi

        # Web Application Discovery Check
        if [[ "${webapp_discovery_check}" == "yes" && ( ! -s "${report_dir}/domains_alive.txt" && "${recon_check}" != "yes" ) ]] ; then
            echo -e "The -wd|--webapp-discovery option requires -r|--recon to discover alive domains first."
            echo -e "Run with -r|--recon to generate domains_alive.txt, then run web application discovery.\n"
            usage
        fi

        if [[ "${webapp_discovery_check}" == "yes" && ${#webapp_port_detect[@]} -eq 0 ]]; then
            echo -e "The -wd|--webapp-discovery option requires a port detection mode."
            echo -e "Add -wld|--webapp-long-detection or -wsd|--webapp-short-detection to specify which ports to probe.\n"
            usage
        fi

        if [[ "${webapp_discovery_check}" != "yes" && ${#webapp_port_detect[@]} -gt 0 ]]; then
            echo -e "The -wld|--webapp-long-detection and -wsd|--webapp-short-detection options require -wd|--webapp-discovery."
            echo -e "Add -wd|--webapp-discovery to enable web application discovery with the specified port detection mode.\n"
            usage
        fi

        # Web Application Enumeration Check
        if [[ "${webapp_enum_check}" == "yes" && ( ! -s "${report_dir}/webapp_consolidated.txt" && "${webapp_discovery_check}" != "yes" ) ]] ; then
            echo -e "The -we|--webapp-enum option requires -wd|--webapp-discovery to discover web applications first."
            echo -e "Run with -wd|--webapp-discovery (and -wsd or -wld) to generate webapp_consolidated.txt, then run enumeration.\n"
            usage
        fi

        if [[ "${webapp_enum_check}" == "yes" && ${#webapp_wordlists[@]} -eq 0 ]]; then
            echo -e "The -we|--webapp-enum option requires at least one wordlist for directory and file discovery."
            echo -e "Add -ww|--webapp-wordlists /path/to/wordlist to specify wordlists for enumeration.\n"
            usage
        fi

        # Web Application Scan Check
        if [[ "${webapp_scan_check}" == "yes" && ( ! -s "${report_dir}/webapp_consolidated.txt" && "${webapp_discovery_check}" != "yes" ) ]] ; then
            echo -e "The -ws|--webapp-scan option requires -wd|--webapp-discovery to discover web applications first."
            echo -e "Run with -wd|--webapp-discovery (and -wsd or -wld) to generate webapp_consolidated.txt, then run scan.\n"
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
