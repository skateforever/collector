#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * urlhaus-src                                           #
#                                                           #
#############################################################

urlhaus-src(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing urlhaus... "
    unset user_agent
    user_agent="$(get_user_agent)"
    echo -e "\ncurl ${curl_options[@]} -H \"User-agent: ${user_agent}\" -X POST -d \"host=${domain}\" \"https://urlhaus-api.abuse.ch/v1/host/\"" >> "${log_execution_file}"
    curl "${curl_options[@]}" -H "User-agent: ${user_agent}" -X POST -d "host=${domain}" "https://urlhaus-api.abuse.ch/v1/host/" > "${tmp_dir}/urlhaus_output.json" 2>> "${log_execution_file}"
    echo "Done!"
    sleep 1
}

urlhaus-src
