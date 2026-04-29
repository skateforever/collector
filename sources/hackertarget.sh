#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * hackertarget-src                                      #
#                                                           #
#############################################################            

hackertarget-src(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing hackertarget... "
    unset user_agent
    user_agent="$(get_user_agent)"
    echo -e "\ncurl ${curl_options[@]} -H \"User-agent: ${user_agent}\" \"${hackertarget_url}${domain}\"" >> "${log_execution_file}"
    curl "${curl_options[@]}" -H "User-agent: ${user_agent}" "${hackertarget_url}${domain}" > "${tmp_dir}/hackertarget_output.txt" 2>> "${log_execution_file}"
    echo "Done!"
    sleep 1
}

hackertarget-src
