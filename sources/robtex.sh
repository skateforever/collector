#!/bin/bash
#############################################################
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * robtex-src                                            #
#                                                           #
#############################################################

robtex-src(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing robtex... "
    unset user_agent
    user_agent="$(get_user_agent)"
    echo -e "\ncurl ${curl_options[@]} -H \"User-agent: ${user_agent}\" \"https://freeapi.robtex.com/pdns/forward/${domain}\" -o ${tmp_dir}/robtex_output.json" >> "${log_execution_file}"
    curl "${curl_options[@]}" "https://freeapi.robtex.com/pdns/forward/${domain}" -o "${tmp_dir}/robtex_output.json" 2>> "${log_execution_file}"
    echo "Done!"
}

robtex-src
