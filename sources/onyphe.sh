#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * onyphe-src                                            #
#                                                           #
#############################################################

onyphe-src(){
    [[ -z "${onyphe_api_key}" ]] && return 0
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing onyphe... "
    : > "${tmp_dir}/onyphe_output.json"
    for onyphe_page in $(seq 1 10); do
        echo -e "\ncurl ${curl_options[@]} -H \"Authorization: bearer ${onyphe_api_key}\" \"https://www.onyphe.io/api/v2/search/?q=domain:${domain}&page=${onyphe_page}&size=100\"" >> "${log_execution_file}"
        onyphe_result="$(curl "${curl_options[@]}" \
            -H "Authorization: bearer ${onyphe_api_key}" \
            "https://www.onyphe.io/api/v2/search/?q=domain:${domain}&page=${onyphe_page}&size=100" 2>> "${log_execution_file}")"
        echo "${onyphe_result}" >> "${tmp_dir}/onyphe_output.json"
        onyphe_count="$(echo "${onyphe_result}" | jq -r '.results | length' 2>/dev/null)"
        onyphe_max_page="$(echo "${onyphe_result}" | jq -r '.max_page // 1' 2>/dev/null)"
        [[ -z "${onyphe_count}" || "${onyphe_count}" -eq 0 || "${onyphe_page}" -ge "${onyphe_max_page}" ]] && break
        sleep 1
    done
    echo "Done!"
}

onyphe-src
