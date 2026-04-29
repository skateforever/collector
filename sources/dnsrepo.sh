#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * dnsrepo-src                                           #
#                                                           #
#############################################################            

dnsrepo-src(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing dnsrepo... "
    unset user_agent
    user_agent="$(get_user_agent)"
    echo -e "\ncurl ${curl_options[@]} -H \"User-agent: ${user_agent}\" https://dnsrepo.noc.org/?domain=${domain}" >> "${log_execution_file}"
    curl "${curl_options[@]}" -H "User-agent: ${user_agent}" "https://dnsrepo.noc.org/?domain=${domain}" -o "${tmp_dir}/dnsrepo_output.html" 2>> "${log_execution_file}"
    echo "Done!"
    sleep 1
}

dnsrepo-src
