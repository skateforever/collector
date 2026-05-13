#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * crt-src                                               #
#                                                           #
#############################################################            

crt-src(){
    cho -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing crt.sh... "
    unset user_agent
    user_agent="$(get_user_agent)"
    echo -e "\ncurl -k -s -H \"User-agent: ${user_agent}\" \"https://crt.sh/?CN=${domain}&output=json\"" \
        >> "${log_execution_file}"
    curl -k -s -H "User-agent: ${user_agent}" "https://crt.sh/?CN=${domain}&output=json" \
        > "${tmp_dir}/crtsh_output.json" \
        2>> "${log_execution_file}"
    echo "Done!"
    sleep 1
}

crt-src
