#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * shodan-src                                            #
#                                                           #
#############################################################            

shodan-src(){
    shodan_use=$(echo "${shodan_use}" | tr '[:upper:]' '[:lower:]')

    if [ -n "${shodan_use}" ] && [ "${shodan_use}" == "yes" ]; then
        if [ "${shodan_use}" == "yes" ]; then
            [[ -n "${shodan_just_scan_main_domain}" ]] && \
                shodan_just_scan_main_domain=$(echo "${shodan_just_scan_main_domain}" | tr '[:upper:]' '[:lower:]')
            if [ -n "${shodan_apikey}" ] && [ ! -s ~/.shodan/api_key ]; then
                shodan init "${shodan_apikey}" > /dev/null
            fi
        fi
        echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing shodan... " | tee -a "${log_execution_file}"
        echo -e "\nshodan search --no-color --fields hostnames hostname:${domain}" >> "${log_execution_file}"
        shodan search --no-color --fields hostnames hostname:"${domain}" \
            > "${tmp_dir}/shodan_output.txt" \
            2>> "${log_execution_file}"
        echo "Done!"
        sleep 1
    fi
}

shodan-src
