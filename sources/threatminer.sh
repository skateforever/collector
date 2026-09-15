#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * threatminer-src                                       #
#                                                           #
#############################################################

threatminer-src(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing threatminer... "
    unset user_agent
    user_agent="$(get_user_agent)"
    echo -e "\ncurl ${curl_options[@]} -H \"User-agent: ${user_agent}\" \"https://api.threatminer.org/v2/domain.php?q=${domain}&rt=5\"" >> "${log_execution_file}"
    curl "${curl_options[@]}" -H "User-agent: ${user_agent}" "https://api.threatminer.org/v2/domain.php?q=${domain}&rt=5" > "${tmp_dir}/threatminer_output.json" 2>> "${log_execution_file}"
    echo "Done!"
    sleep 1
}

threatminer-src
