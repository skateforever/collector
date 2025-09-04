#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * whoisxmlapi                                           #
#                                                           #
#############################################################            

whoisxmlapi-src(){
    if [[ -n "${whoisxmlapi_api_key}" ]] && [[ -n "${whoisxmlapi_subdomain_url}" ]]; then
        echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing whoisxmlapi... "
        echo -e "\ncurl ${curl_options[@]} -X POST \"${whoisxmlapi_subdomain_url}\" -H \"Content-Type: application/json\" \
                --data '{\"apiKey\": \"${whoisxmlapi_api_key}\", \"domains\": {\"include\": [\"${domain}\"]},\"subdomains\": {\"include\": [],\"exclude\": []}}' \
                | jq -r '.domainsList[]'" >> "${log_execution_file}"
        curl "${curl_options[@]}" -X POST "${whoisxmlapi_subdomain_url}" -H "Content-Type: application/json" \
            --data '{"apiKey": "'${whoisxmlapi_api_key}'", "domains": {"include": ["'${domain}'"]},"subdomains": {"include": [],"exclude": []}}' \
            > "${tmp_dir}/whoisxmlapi_output.json" 2>> "${log_execution_file}"
        echo "Done!"
    fi
    sleep 1
}

whoisxmlapi-src
