#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * merklemap-src                                         #
#                                                           #
#############################################################

merklemap-src(){
    [[ -z "${merklemap_api_key}" ]] && return 0
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing merklemap... "
    : > "${tmp_dir}/merklemap_output.json"
    for merklemap_page in $(seq 0 9); do
        echo -e "\ncurl ${curl_options[@]} -H \"Authorization: Bearer ${merklemap_api_key}\" \"https://api.merklemap.com/v1/search?query=${domain}&page=${merklemap_page}&type=distance\"" >> "${log_execution_file}"
        merklemap_result="$(curl "${curl_options[@]}" \
            -H "Authorization: Bearer ${merklemap_api_key}" \
            "https://api.merklemap.com/v1/search?query=${domain}&page=${merklemap_page}&type=distance" 2>> "${log_execution_file}")"
        echo "${merklemap_result}" >> "${tmp_dir}/merklemap_output.json"
        merklemap_has_more="$(echo "${merklemap_result}" | jq -r '.next // .has_more // false' 2>/dev/null)"
        merklemap_count="$(echo "${merklemap_result}" | jq -r '.results | length' 2>/dev/null)"
        [[ "${merklemap_has_more}" == "false" || -z "${merklemap_count}" || "${merklemap_count}" -eq 0 ]] && break
        sleep 1
    done
    echo "Done!"
}

merklemap-src
