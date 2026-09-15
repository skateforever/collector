#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * bevigil-src                                           #
#                                                           #
#############################################################

bevigil-src(){
    [[ -z "${bevigil_api_key}" ]] && return 0
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing bevigil... "
    unset user_agent
    user_agent="$(get_user_agent)"
    echo -e "\ncurl ${curl_options[@]} -H \"X-Access-Token: ${bevigil_api_key}\" -H \"User-agent: ${user_agent}\" \"https://osint.bevigil.com/api/${domain}/subdomains/\"" >> "${log_execution_file}"
    curl "${curl_options[@]}" \
        -H "X-Access-Token: ${bevigil_api_key}" \
        -H "User-agent: ${user_agent}" \
        "https://osint.bevigil.com/api/${domain}/subdomains/" > "${tmp_dir}/bevigil_output.json" 2>> "${log_execution_file}"
    echo "Done!"
    sleep 1
}

bevigil-src
