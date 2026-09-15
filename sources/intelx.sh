#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * intelx-src                                            #
#                                                           #
#############################################################

intelx-src(){
    [[ -z "${intelx_api_key}" ]] && return 0
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing intelx... "
    unset user_agent
    user_agent="$(get_user_agent)"
    echo -e "\ncurl ${curl_options[*]} -H \"User-agent: ${user_agent}\" -X POST \"https://2.intelx.io/phonebook/search?k=[REDACTED]\" -d '{\"term\":\"*.${domain}\",\"buckets\":[],\"lookuplevel\":0,\"maxresults\":100000,\"timeout\":0,\"datefrom\":\"\",\"dateto\":\"\",\"sort\":4,\"media\":0,\"terminate\":[],\"target\":1}'   " >> "${log_execution_file}"
    intelx_id="$(curl "${curl_options[@]}" \
        -H "User-agent: ${user_agent}" \
        -H "Content-Type: application/json" \
        -X POST "https://2.intelx.io/phonebook/search?k=${intelx_api_key}" \
        -d "{\"term\":\"*.${domain}\",\"buckets\":[],\"lookuplevel\":0,\"maxresults\":100000,\"timeout\":0,\"datefrom\":\"\",\"dateto\":\"\",\"sort\":4,\"media\":0,\"terminate\":[],\"target\":1}" 2>> "${log_execution_file}" \
        | jq -r '.id' 2>/dev/null)"
    sleep 2
    echo -e "\ncurl ${curl_options[*]} -H \"User-agent: ${user_agent}\" \"https://2.intelx.io/phonebook/result?k=[REDACTED]&id=${intelx_id}&limit=100000&offset=0\"" >> "${log_execution_file}"
    curl "${curl_options[@]}" \
        -H "User-agent: ${user_agent}" \
        "https://2.intelx.io/phonebook/result?k=${intelx_api_key}&id=${intelx_id}&limit=100000&offset=0" > "${tmp_dir}/intelx_output.json" 2>> "${log_execution_file}"
    echo "Done!"
    sleep 1
}

intelx-src
