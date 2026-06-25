#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * leakix-src                                            #
#                                                           #
#############################################################

leakix-src(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing leakix... "
    unset user_agent
    user_agent="$(get_user_agent)"
    if [[ -n "${leakix_api_key}" ]]; then
        echo -e "\ncurl ${curl_options[@]} -H \"api-key: ${leakix_api_key}\" -H \"accept: application/json\" -H \"User-agent: ${user_agent}\" \"https://leakix.net/api/subdomains/${domain}\"" >> "${log_execution_file}"
        curl "${curl_options[@]}" \
            -H "api-key: ${leakix_api_key}" \
            -H "accept: application/json" \
            -H "User-agent: ${user_agent}" \
            "https://leakix.net/api/subdomains/${domain}" > "${tmp_dir}/leakix_output.json" 2>> "${log_execution_file}"
    else
        echo -e "\ncurl ${curl_options[@]} -H \"accept: application/json\" -H \"User-agent: ${user_agent}\" \"https://leakix.net/api/subdomains/${domain}\"" >> "${log_execution_file}"
        curl "${curl_options[@]}" \
            -H "accept: application/json" \
            -H "User-agent: ${user_agent}" \
            "https://leakix.net/api/subdomains/${domain}" > "${tmp_dir}/leakix_output.json" 2>> "${log_execution_file}"
    fi
    echo "Done!"
    sleep 1
}

leakix-src
