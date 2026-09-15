#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * jldc-src                                              #
#                                                           #
#############################################################

jldc-src(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing jldc... "
    unset user_agent
    user_agent="$(get_user_agent)"
    echo -e "\ncurl ${curl_options[@]} -H \"User-agent: ${user_agent}\" \"https://jldc.me/anubis/subdomains/${domain}\"" >> "${log_execution_file}"
    curl "${curl_options[@]}" -H "User-agent: ${user_agent}" "https://jldc.me/anubis/subdomains/${domain}" > "${tmp_dir}/jldc_output.json" 2>> "${log_execution_file}"
    echo "Done!"
    sleep 1
}

jldc-src
