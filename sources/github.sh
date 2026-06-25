#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * github-src                                            #
#                                                           #
#############################################################

github-src(){
    [[ -z "${github_token}" ]] && return 0
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing github... "
    : > "${tmp_dir}/github_output.json"
    for github_page in $(seq 1 10); do
        echo -e "\ncurl ${curl_options[@]} -H \"Authorization: token ${github_token}\" -H \"Accept: application/vnd.github.v3.text-match+json\" -H \"X-GitHub-Api-Version: 2022-11-28\" \"https://api.github.com/search/code?q=${domain}&per_page=100&page=${github_page}\"" >> "${log_execution_file}"
        github_result="$(curl "${curl_options[@]}" \
            -H "Authorization: token ${github_token}" \
            -H "Accept: application/vnd.github.v3.text-match+json" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            "https://api.github.com/search/code?q=${domain}&per_page=100&page=${github_page}" 2>> "${log_execution_file}")"
        echo "${github_result}" >> "${tmp_dir}/github_output.json"
        [[ "$(echo "${github_result}" | jq -r '.items | length' 2>/dev/null)" -eq 0 ]] && break
        sleep 2
    done
    echo "Done!"
}

github-src
