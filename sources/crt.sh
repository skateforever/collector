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
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing crt.sh... "
    unset user_agent
    user_agent="$(get_user_agent)"
    attempt=0
    while [[ ${attempt} -lt 3 ]]; do
        attempt=$(( attempt + 1 ))
        echo -e "\ncurl ${curl_options_slow[@]} -H \"User-agent: ${user_agent}\" \"https://crt.sh/?q=%25.${domain}&output=json\"" >> "${log_execution_file}"
        curl "${curl_options_slow[@]}" -H "User-agent: ${user_agent}" "https://crt.sh/?q=%25.${domain}&output=json" > "${tmp_dir}/crtsh_output.json" 2>> "${log_execution_file}"
        [[ -s "${tmp_dir}/crtsh_output.json" ]] && head -c 1 "${tmp_dir}/crtsh_output.json" | grep -qE '^\[|\{' && break
        sleep $(( attempt * 10 ))
    done
    head -c 1 "${tmp_dir}/crtsh_output.json" | grep -qE '^\[|\{' || echo "[]" > "${tmp_dir}/crtsh_output.json"
    echo "Done!"
    sleep 1
}

crt-src
