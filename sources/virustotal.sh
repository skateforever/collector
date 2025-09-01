#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * virustotal                                            #
#                                                           #
#############################################################            

virustotal-src(){
    if [[ -n "${virustotal_api_url}" ]] && [[ -n "${virustotal_api_key}" ]]; then
        echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing virus total... " | tee -a "${log_execution_file}"
        echo -e "\ncurl ${curl_options[@]} -H \"X-Apikey: ${virustotal_api_key}\" \"${virustotal_api_url}/${domain}/subdomains?limit=40\"" >> "${log_execution_file}"
        virustotal_api_check=$(curl "${curl_options[@]}" -w "%{http_code}\n" -H "X-Apikey: ${virustotal_api_key}" "${virustotal_api_url}/${domain}/subdomains?limit=40" -o /dev/null)
        if [ "${virustotal_api_check}" -eq 200 ]; then
            curl "${curl_options[@]}" -H "X-Apikey: ${virustotal_api_key}" "${virustotal_api_url}/${domain}/subdomains?limit=40" \
                > "${tmp_dir}/virustotal_output.json" 2>> "${log_execution_file}"
            sleep 1
        fi
        echo "Done!"
    fi
}

virustotal-src
