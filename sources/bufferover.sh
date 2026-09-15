#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * bufferover-src                                        #
#                                                           #
#############################################################

bufferover-src(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing bufferover... "
    unset user_agent
    user_agent="$(get_user_agent)"
    echo -e "\ncurl ${curl_options[@]} -H \"User-agent: ${user_agent}\" \"https://tls.bufferover.run/dns?q=.${domain}\"" >> "${log_execution_file}"
    curl "${curl_options[@]}" -H "User-agent: ${user_agent}" "https://tls.bufferover.run/dns?q=.${domain}" > "${tmp_dir}/bufferover_output.json" 2>> "${log_execution_file}"
    echo "Done!"
    sleep 1
}

bufferover-src
