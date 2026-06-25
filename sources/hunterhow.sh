#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * hunterhow-src                                         #
#                                                           #
#############################################################

hunterhow-src(){
    [[ -z "${hunterhow_api_key}" ]] && return 0
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing hunterhow... "
    : > "${tmp_dir}/hunterhow_output.json"
    for hunterhow_page in $(seq 1 10); do
        echo -e "\ncurl ${curl_options[@]} \"https://api.hunter.how/search?query=domain%3A%22${domain}%22&page=${hunterhow_page}&page_size=100&api-key=${hunterhow_api_key}\"" >> "${log_execution_file}"
        hunterhow_result="$(curl "${curl_options[@]}" \
            "https://api.hunter.how/search?query=domain%3A%22${domain}%22&page=${hunterhow_page}&page_size=100&api-key=${hunterhow_api_key}" 2>> "${log_execution_file}")"
        echo "${hunterhow_result}" >> "${tmp_dir}/hunterhow_output.json"
        hunterhow_assets="$(echo "${hunterhow_result}" | jq -r '.data.assets | length' 2>/dev/null)"
        [[ -z "${hunterhow_assets}" || "${hunterhow_assets}" -eq 0 ]] && break
        sleep 1
    done
    echo "Done!"
}

hunterhow-src
