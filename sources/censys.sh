#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * censys-src                                            #
#                                                           #
#############################################################

censys-src(){
    [[ -z "${censys_api_id}" ]] || [[ -z "${censys_api_secret}" ]] && return 0
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing censys... "
    : > "${tmp_dir}/censys_output.json"
    censys_cursor=""
    censys_page=0
    while true; do
        censys_page=$(( censys_page + 1 ))
        if [[ -n "${censys_cursor}" ]]; then
            censys_params="q=parsed.names%3A+%25.${domain}&fields=parsed.names&per_page=100&cursor=${censys_cursor}"
        else
            censys_params="q=parsed.names%3A+%25.${domain}&fields=parsed.names&per_page=100"
        fi
        echo -e "\n$(redact_secrets "curl ${curl_options[@]} -u ${censys_api_id}:${censys_api_secret} \"https://search.censys.io/api/v2/certificates/search?${censys_params}\"")" >> "${log_execution_file}"
        censys_result="$(curl "${curl_options[@]}" \
            -u "${censys_api_id}:${censys_api_secret}" \
            "https://search.censys.io/api/v2/certificates/search?${censys_params}" 2>> "${log_execution_file}")"
        echo "${censys_result}" >> "${tmp_dir}/censys_output.json"
        censys_cursor="$(echo "${censys_result}" | jq -r '.result.links.next // empty' 2>/dev/null)"
        [[ -z "${censys_cursor}" ]] && break
        sleep 1
    done
    echo "Done!"
}

censys-src
