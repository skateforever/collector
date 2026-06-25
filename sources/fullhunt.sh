#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * fullhunt-src                                          #
#                                                           #
#############################################################

fullhunt-src(){
    [[ -z "${fullhunt_api_key}" ]] && return 0
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing fullhunt... "
    unset user_agent
    user_agent="$(get_user_agent)"
    echo -e "\ncurl ${curl_options[@]} -H \"X-API-Key: ${fullhunt_api_key}\" -H \"User-agent: ${user_agent}\" \"https://fullhunt.io/api/v1/domain/${domain}/details\"" >> "${log_execution_file}"
    curl "${curl_options[@]}" \
        -H "X-API-Key: ${fullhunt_api_key}" \
        -H "User-agent: ${user_agent}" \
        "https://fullhunt.io/api/v1/domain/${domain}/details" > "${tmp_dir}/fullhunt_output.json" 2>> "${log_execution_file}"
    echo "Done!"
    sleep 1
}

fullhunt-src
