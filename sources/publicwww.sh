#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * publicwww-src                                         #
#                                                           #
#############################################################

publicwww-src(){
    [[ -z "${publicwww_api_key}" ]] && return 0
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing publicwww... "
    unset user_agent
    user_agent="$(get_user_agent)"
    echo -e "\ncurl ${curl_options[@]} -H \"User-agent: ${user_agent}\" \"https://publicwww.com/websites/%22.${domain}%22/?export=csv&k=${publicwww_api_key}\"" >> "${log_execution_file}"
    curl "${curl_options[@]}" \
        -H "User-agent: ${user_agent}" \
        "https://publicwww.com/websites/%22.${domain}%22/?export=csv&k=${publicwww_api_key}" > "${tmp_dir}/publicwww_output.txt" 2>> "${log_execution_file}"
    echo "Done!"
    sleep 1
}

publicwww-src
