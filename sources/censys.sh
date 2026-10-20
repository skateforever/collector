#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * censys-src                                            #
#                                                           #
#############################################################
#
# Censys Search v2 (search.censys.io/api/v2) was shut down 2026-09-30; the
# live API now is the Platform API (api.platform.censys.io), confirmed
# against its public OpenAPI spec at /openapi.json. It authenticates with a
# Bearer Personal Access Token (censys_platform_api_token) instead of the
# old API ID+secret pair — those are for the dead v2 API and no longer work.
#
# /v3/global/search/convert translates the same Censys Search Language query
# this script always used ("parsed.names: *.domain") into CenQL, so this
# doesn't depend on hand-guessing Platform's query field names — Censys's
# own converter does that translation.

censys-src(){
    [[ -z "${censys_platform_api_token}" ]] && return 0
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing censys... "
    : > "${tmp_dir}/censys_output.json"
    local censys_hits_tmp="${tmp_dir}/censys_hits.tmp"
    : > "${censys_hits_tmp}"
    local -a censys_auth=(-H "Authorization: Bearer ${censys_platform_api_token}" -H "Content-Type: application/json")

    local censys_convert_body
    censys_convert_body="$(jq -nc --arg q "parsed.names: *.${domain}" '{queries:[$q]}')"
    echo -e "\ncurl ${curl_options[@]} ${censys_auth[*]} -d '${censys_convert_body}' \"https://api.platform.censys.io/v3/global/search/convert\"" >> "${log_execution_file}"
    local censys_convert_result censys_query
    censys_convert_result="$(curl "${curl_options[@]}" "${censys_auth[@]}" \
        -d "${censys_convert_body}" \
        "https://api.platform.censys.io/v3/global/search/convert" 2>> "${log_execution_file}")"
    censys_query="$(echo "${censys_convert_result}" | jq -r '.result[0].converted_query // empty' 2>/dev/null)"

    if [[ -z "${censys_query}" ]]; then
        echo "censys: query conversion failed, response was: ${censys_convert_result}" >> "${log_execution_file}"
        echo "Fail!"
        return 0
    fi

    local censys_page_token="" censys_page=0 censys_max_pages=10
    while true; do
        censys_page=$(( censys_page + 1 ))
        [[ "${censys_page}" -gt "${censys_max_pages}" ]] && break
        local censys_body
        if [[ -n "${censys_page_token}" ]]; then
            censys_body="$(jq -nc --arg q "${censys_query}" --arg pt "${censys_page_token}" '{query:$q, page_size:100, page_token:$pt}')"
        else
            censys_body="$(jq -nc --arg q "${censys_query}" '{query:$q, page_size:100}')"
        fi
        echo -e "\ncurl ${curl_options[@]} ${censys_auth[*]} -d '${censys_body}' \"https://api.platform.censys.io/v3/global/search/query\"" >> "${log_execution_file}"
        local censys_result
        censys_result="$(curl "${curl_options[@]}" "${censys_auth[@]}" -d "${censys_body}" \
            "https://api.platform.censys.io/v3/global/search/query" 2>> "${log_execution_file}")"
        echo "${censys_result}" | jq -c '.result.hits[]?' 2>/dev/null >> "${censys_hits_tmp}"
        censys_page_token="$(echo "${censys_result}" | jq -r '.result.next_page_token // empty' 2>/dev/null)"
        [[ -z "${censys_page_token}" ]] && break
        sleep 1
    done

    # Normalize certificate_v1.resource.names (Platform shape) back into the
    # same {"result":{"hits":[{"parsed":{"names":[...]}}]}} shape v2 used, so
    # the parser in functions/files.sh (.result.hits[]?.parsed?.names[]?)
    # doesn't need to know Platform's schema changed underneath it.
    jq -sc '{"result":{"hits": (map(select(.certificate_v1.resource.names)) | map({"parsed":{"names": .certificate_v1.resource.names}}))}}' \
        "${censys_hits_tmp}" > "${tmp_dir}/censys_output.json" 2>/dev/null
    echo "Done!"
}

censys-src
