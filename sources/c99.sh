#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * c99-src                                               #
#                                                           #
#############################################################

c99-src(){
    [[ -z "${c99_api_key}" ]] && return 0
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing c99... "
    unset user_agent
    user_agent="$(get_user_agent)"
    echo -e "\ncurl ${curl_options[@]} -H \"User-agent: ${user_agent}\" \"https://api.c99.nl/subdomainfinder?key=${c99_api_key}&domain=${domain}&json\"" >> "${log_execution_file}"
    curl "${curl_options[@]}" \
        -H "User-agent: ${user_agent}" \
        "https://api.c99.nl/subdomainfinder?key=${c99_api_key}&domain=${domain}&json" > "${tmp_dir}/c99_output.json" 2>> "${log_execution_file}"
    echo "Done!"
    sleep 1
}

c99-src
