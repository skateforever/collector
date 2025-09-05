#!/bin/bash
#############################################################
# Verify the execution and parameter dependency             #
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * check_execution                                       #
#   * check_parameter_dependency_domain                     #
#   * check_is_know_target                                  #
#                                                           #
#############################################################

# Checking if the script has the main parameters needed
check_execution(){
    if [[ -z "${url_2_verify}" ]] && [[ -z "${domain}" ]] && [[ ! -s "${domain_list}" ]]; then
        echo -e "You need at least one option \"-u|--url\", \"-d|--domain\" OR \"-dl|--domain-list\" to execute this script!\n"
        usage
    fi
}

# Checking the runtime parameter dependency for recon
check_parameter_dependency_domain(){
    if [[ -n "${domain}" ]] || [[ -s "${domain_list}" ]] && [[ -z "${url_2_verify}" ]]; then
        if [[ "${args_count}" -gt 9 ]]; then 
            echo -e "You are trying to pass a number of parameters beyond what is necessary for this collector reconnaissance option \"${yellow}-d|--domain${reset}\".\n"
            usage
        fi
 
        if [[ ${#webapp_port_detect[@]} -eq 0 ]] && [[ "${only_webapp_enum}" == "no" ]]; then
            echo -e "You need to specify at least one of these options sort (-ws|--web-short-detection) or long (-wl|--web-long-detection) web detection!\n"
            usage
        fi

        if [[ -z "${webapp_tool_detection}" ]] && [[ "${only_webapp_enum}" == "no" ]]; then
            echo -e "You need to inform one of these tools ${bold}${yellow}curl${reset}${normal} or ${bold}${yellow}httpx${reset}${normal} to perform web application detection.\n"
            usage
       fi
    fi

    if [[ -n "${url_2_verify}" ]] && [[ -z "${domain}" ]] && [[ ! -s "${domain_list}" ]]; then
        if [[ "${args_count}" -gt 4 ]]; then
            echo -e "You are trying to pass a number of parameters beyond what is necessary for this collector reconnaissance option \"${yellow}-u|--url${reset}\".\n"
            usage
        fi
    fi

    if [[ "${only_webapp_enum}" == "yes" ]] && [[ ${#webapp_wordlists[@]} -eq 0 ]]; then
        echo -e "Please, ${yellow}make sure${reset} you have at least one wordlist to web directory and file discovery!\n"
        usage
    fi
}

# Checking if is a know target to get the cursor position
check_is_known_target(){
    if [[ -n "$1" ]] && [[ -d "${output_dir}/$1" ]]; then
        echo "This is a known target."
    fi
}
