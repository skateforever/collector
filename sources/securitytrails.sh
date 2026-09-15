#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * securitytrails-src                                    #
#                                                           #
#############################################################            

securitytrails-src(){
    if [[ -n "${securitytrails_api_key}" ]]; then
        echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing security trails... "
        unset user_agent
        user_agent="$(get_user_agent)"
        echo -e "\ncurl ${curl_options[@]} -H \"User-agent: ${user_agent}\" -H 'Accept: application/json' -H \"APIKEY: ${securitytrails_api_key}\" \"${securitytrails_api_url}/ping\"" \
            >> "${log_execution_file}"
        # Capture the raw /ping body before handing it to jq — piping curl
        # straight into jq (the old approach) discards the response on a
        # parse failure, so an auth/rate-limit error came back as a bare
        # "Fail!" with no way to see what the API actually returned.
        local securitytrails_ping_response
        securitytrails_ping_response="$(curl "${curl_options[@]}" -H "User-agent: ${user_agent}" -H "APIKEY: ${securitytrails_api_key}" -H 'Accept: application/json' "${securitytrails_api_url}/ping" 2>> "${log_execution_file}")"
        securitytrails_api_check="$(echo "${securitytrails_ping_response}" | jq -r '.success' 2>> "${log_execution_file}")"
        if [[ -n "${securitytrails_api_check}" ]] &&  [[ "${securitytrails_api_check}" == "true" ]] ; then
            echo -e "\ncurl ${curl_options[@]} -H \"User-agent: ${user_agent}\" -H 'Accept: application/json' -H \"APIKEY: ${securitytrails_api_key}\" \"${securitytrails_api_url}/domain/${domain}/subdomains?children_only=false&include_inactive=true\"" \
                >> "${log_execution_file}"
            curl "${curl_options[@]}" -H "User-agent: ${user_agent}" \
                -H 'Accept: application/json' -H "APIKEY: ${securitytrails_api_key}" \
                "${securitytrails_api_url}/domain/${domain}/subdomains?children_only=false&include_inactive=true" \
                >> "${tmp_dir}/securitytrails_output.json" 2>> "${log_execution_file}"
            sleep 1
            echo "Done!"
        else
            echo "securitytrails: /ping check failed, response was: ${securitytrails_ping_response}" >> "${log_execution_file}"
            echo "Fail!"
        fi
    fi
}

securitytrails-src
