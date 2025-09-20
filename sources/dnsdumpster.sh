#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * dnsdumpster-src                                       #
#                                                           #
#############################################################            

dnsdumpster-src(){
    if [ -n "${dnsdumpster_api_key}" ]; then
        echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing dns dumpster... "
        echo -e "\ncurl ${curl_options[@]} -H \"X-API-Key: ${dnsdumpster_api_key}\" ${dnsdumpster_url}/${domain}" >> "${log_execution_file}"
        curl ${curl_options[@]} -H "X-API-Key: ${dnsdumpster_api_key}" "${dnsdumpster_url}/${domain}" >> "${tmp_dir}/dnsdumpster_output.json" 2>> "${log_execution_file}"
        echo "Done!"
        sleep 1
    fi
}

dnsdumpster-src
