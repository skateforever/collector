#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * urlscan-src                                           #
#                                                           #
#############################################################            

urlscan-src(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing urlscan... "
    unset user_agent
    user_agent="$(get_user_agent)"
    echo -e "\ncurl ${curl_options[@]} -H \"User-agent: ${user_agent}\" \"https://urlscan.io/api/v1/search/?q=domain:${domain}\"" >> "${log_execution_file}"
    curl "${curl_options[@]}" -H "User-agent: ${user_agent}" "https://urlscan.io/api/v1/search/?q=domain:${domain}" -o "${tmp_dir}/urlscan_output.json" 2>> "${log_execution_file}"
    echo "Done!"
    sleep 1
}

urlscan-src
