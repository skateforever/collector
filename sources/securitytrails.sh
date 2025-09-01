#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * securitytrails-src                                    #
#                                                           #
#############################################################            

securitytrails-src(){
    if [[ -n "${securitytrails_api_key}" ]]; then
        echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing security trails... " | tee -a "${log_execution_file}"
        echo -e "\ncurl ${curl_options[@]} -H 'Accept: application/json' -H \"APIKEY: ${securitytrails_api_key}\" \
            \"${securitytrails_api_url}/domain/${domain}/subdomains?children_only=false&include_inactive=true\"" \
            >> "${log_execution_file}"
        securitytrails_api_check=$(curl "${curl_options[@]}" "${securitytrails_api_url}/ping" -H "APIKEY: ${securitytrails_api_key}" -H 'Accept: application/json' | jq -r '.success' 2>> ${log_execution_file})
        if [ "${securitytrails_api_check}" == "true" ]; then
            curl "${curl_options[@]}" -H 'Accept: application/json' -H "APIKEY: ${securitytrails_api_key}" \
                "${securitytrails_api_url}/domain/${domain}/subdomains?children_only=false&include_inactive=true" \
                >> "${tmp_dir}/securitytrails_output.json" 2>> "${log_execution_file}"
            echo "Done!"
            sleep 1
        fi
    fi
}

securitytrails-src
