#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * commoncrawl-src                                       #
#                                                           #
#############################################################            

commoncrawl-src(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing commoncrawl... "
    unset user_agent
    user_agent="$(get_user_agent)"
    echo -e "\ncurl ${curl_options_slow[@]} -H \"User-agent: ${user_agent}\" \"${commoncrawl_url}\" | jq --raw-output .[0]'.\"cdx-api\"'" >> "${log_execution_file}"
    commoncrawl_db=$(curl "${curl_options_slow[@]}" -H "User-agent: ${user_agent}" "${commoncrawl_url}" | jq --raw-output .[0]'."cdx-api"' 2>> "${log_execution_file}")
    echo "${commoncrawl_db}" >> "${log_execution_file}"
    echo "curl ${curl_options_slow[@]} -H \"User-agent: ${user_agent}\" \"${commoncrawl_db}?url=*.${domain}/&output=json\"" >> "${log_execution_file}"
    curl "${curl_options_slow[@]}" -H "User-agent: ${user_agent}" "${commoncrawl_db}?url=*.${domain}/&output=json" > "${tmp_dir}/commoncrawl_output.json" 2>> "${log_execution_file}"
    echo "Done!"
    sleep 1
}

commoncrawl-src
