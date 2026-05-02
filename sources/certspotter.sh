#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * certspotter-src                                       #
#                                                           #
#############################################################            

certspotter-src(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing certspotter... "
    unset user_agent
    user_agent="$(get_user_agent)"
    echo -e "\ncurl ${curl_options[@]} -H \"User-agent: ${user_agent}\" \"https://api.certspotter.com/v1/issuances?domain=${domain}&include_subdomains=true&expand=dns_names\" | jq -r '.[].dns_names[]'" >> "${log_execution_file}"
    curl "${curl_options[@]}" -H "User-agent: ${user_agent}" "https://api.certspotter.com/v1/issuances?domain=${domain}&include_subdomains=true&expand=dns_names" > "${tmp_dir}/certspotter_output.json" 2>> "${log_execution_file}"
    echo "Done!"
    sleep 1
}

certspotter-src
