#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * subdomaincenter-src                                           #
#                                                           #
#############################################################            

subdomaincenter-src(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing subdomain center... "
    unset user_agent
    user_agent="$(get_user_agent)"
    local tmp_out="${tmp_dir}/subdomaincenter_output.json"

    echo -e "\ncurl ${curl_options[@]} -H \"User-agent: ${user_agent}\" \"https://api.subdomain.center/?domain=${domain}\"" >> "${log_execution_file}"
    curl "${curl_options[@]}" -H "User-agent: ${user_agent}" \
        "https://api.subdomain.center/?domain=${domain}" \
        -o "${tmp_out}" 2>> "${log_execution_file}"

    # api.subdomain.center may return a Cloudflare challenge page (error code:
    # 1010) or other non-JSON content when bot detection triggers.
    # Accept the result only when it is a non-empty JSON array/object.
    if ! ([[ -s "${tmp_out}" ]] && head -c 1 "${tmp_out}" | grep -qE '^\[|\{'); then
        echo -e "\n${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} subdomaincenter returned non-JSON response (possible Cloudflare block)." \
            >> "${log_execution_file}"
        echo "[]" > "${tmp_out}"
    fi

    echo "Done!"
    sleep 1
}

subdomaincenter-src
