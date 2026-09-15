#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * greynoise-src                                         #
#                                                           #
#############################################################

greynoise-src(){
    [[ -z "${greynoise_api_key}" ]] && return 0
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing greynoise... "
    unset user_agent
    user_agent="$(get_user_agent)"
    echo -e "\ncurl ${curl_options[@]} -H \"Authorization: Bearer ${greynoise_api_key}\" -H \"User-agent: ${user_agent}\" \"https://api.greynoise.io/v3/query?query=metadata.rdns:.${domain}&limit=10000\"" >> "${log_execution_file}"
    curl "${curl_options[@]}" \
        -H "Authorization: Bearer ${greynoise_api_key}" \
        -H "User-agent: ${user_agent}" \
        "https://api.greynoise.io/v3/query?query=metadata.rdns:.${domain}&limit=10000" > "${tmp_dir}/greynoise_output.json" 2>> "${log_execution_file}"
    echo "Done!"
    sleep 1
}

greynoise-src
