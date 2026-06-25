#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * chaos-src                                             #
#                                                           #
#############################################################

chaos-src(){
    [[ -z "${chaos_api_key}" ]] && return 0
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing chaos... "
    unset user_agent
    user_agent="$(get_user_agent)"
    echo -e "\ncurl ${curl_options[@]} -H \"Authorization: ${chaos_api_key}\" -H \"User-agent: ${user_agent}\" \"https://dns.projectdiscovery.io/dns/${domain}/subdomains\"" >> "${log_execution_file}"
    curl "${curl_options[@]}" \
        -H "Authorization: ${chaos_api_key}" \
        -H "User-agent: ${user_agent}" \
        "https://dns.projectdiscovery.io/dns/${domain}/subdomains" > "${tmp_dir}/chaos_output.json" 2>> "${log_execution_file}"
    echo "Done!"
    sleep 1
}

chaos-src
