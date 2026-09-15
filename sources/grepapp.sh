#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * grepapp-src                                           #
#                                                           #
#############################################################

grepapp-src(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing grepapp... "
    unset user_agent
    : > "${tmp_dir}/grepapp_output.json"
    for grepapp_page in 1 2 3 4 5; do
        user_agent="$(get_user_agent)"
        echo -e "\ncurl ${curl_options[@]} -H \"User-agent: ${user_agent}\" \"https://grep.app/api/search?q=${domain}&page=${grepapp_page}&format=e\"" >> "${log_execution_file}"
        curl "${curl_options[@]}" \
            -H "User-agent: ${user_agent}" \
            -H "Accept: application/json" \
            "https://grep.app/api/search?q=${domain}&page=${grepapp_page}&format=e" >> "${tmp_dir}/grepapp_output.json" 2>> "${log_execution_file}"
        sleep 1
    done
    echo "Done!"
}

grepapp-src
