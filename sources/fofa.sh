#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * fofa-src                                              #
#                                                           #
#############################################################

fofa-src(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing fofa... "
    unset user_agent
    user_agent="$(get_user_agent)"
    if [[ -n "${fofa_api_key}" ]]; then
        fofa_query="$(echo -n "domain=\"${domain}\"" | base64 -w 0)"
        echo -e "\ncurl ${curl_options[@]} -H \"User-agent: ${user_agent}\" \"https://fofa.so/api/v1/search/all?key=${fofa_api_key}&qbase64=${fofa_query}&fields=domain,host&size=1000&full=true\"" >> "${log_execution_file}"
        curl "${curl_options[@]}" \
            -H "User-agent: ${user_agent}" \
            "https://fofa.so/api/v1/search/all?key=${fofa_api_key}&qbase64=${fofa_query}&fields=domain,host&size=1000&full=true" > "${tmp_dir}/fofa_output.json" 2>> "${log_execution_file}"
    else
        fofa_query="$(echo -n "domain=\"${domain}\"" | base64 -w 0)"
        echo -e "\ncurl ${curl_options[@]} -H \"User-agent: ${user_agent}\" \"https://fofa.so/result?qbase64=${fofa_query}\"" >> "${log_execution_file}"
        curl "${curl_options[@]}" -L \
            -H "User-agent: ${user_agent}" \
            -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
            "https://fofa.so/result?qbase64=${fofa_query}" > "${tmp_dir}/fofa_output.html" 2>> "${log_execution_file}"
    fi
    echo "Done!"
    sleep 1
}

fofa-src
