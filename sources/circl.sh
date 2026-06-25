#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * circl-src                                             #
#                                                           #
#############################################################

circl-src(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing circl... "
    unset user_agent
    user_agent="$(get_user_agent)"
    echo -e "\ncurl ${curl_options[@]} -H \"User-agent: ${user_agent}\" \"https://www.circl.lu/pdns/query/${domain}\"" >> "${log_execution_file}"
    curl "${curl_options[@]}" -H "User-agent: ${user_agent}" "https://www.circl.lu/pdns/query/${domain}" > "${tmp_dir}/circl_output.txt" 2>> "${log_execution_file}"
    echo "Done!"
    sleep 1
}

circl-src
