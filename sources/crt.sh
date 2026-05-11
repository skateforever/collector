#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * crt-src                                               #
#                                                           #
#############################################################            

crt-src(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing crt.sh... "
    unset user_agent
    user_agent="$(get_user_agent)"
    echo -e "\ncurl ${curl_options[@]} -H \"User-agent: ${user_agent}\" \"https://crt.sh/?CN=${domain}&output=json\" | jq -r '.[].name_value'" >> "${log_execution_file}"
    curl "${curl_options[@]}" -H "User-agent: ${user_agent}" "https://crt.sh/?CN=${domain}&output=json" \
        > "${tmp_dir}/crtsh_output.json" \
        2>> "${log_execution_file}"
    
    if [ -s "${tmp_dir}/crtsh_output.json" ]; then
        jq -r '.[].name_value' "${tmp_dir}/crtsh_output.json" 2>/dev/null | sed 's/\*\.//g' | sort -u > "${tmp_dir}/crtsh.tmp"
    fi
    sleep 1
}

crt-src
