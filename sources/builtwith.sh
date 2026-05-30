#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * builitwith                                            #
#                                                           #
#############################################################            

builtwith-src(){
    if [[ -n "${builtwith_api_key}" ]] && [[ -n "${builtwith_api_url}" ]]; then
        unset user_agent
        user_agent="$(get_user_agent)"
        echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing builtwith subdomain... "
        echo -e "\n$(redact_secrets "curl ${curl_options[@]} -H \"User-agent: ${user_agent}\" ${builtwith_api_url}/v21/api.json?KEY=${builtwith_api_key}&LOOKUP=${domain}")" >> "${log_execution_file}"
        curl "${curl_options[@]}" -H "User-agent: ${user_agent}" "${builtwith_api_url}/v21/api.json?KEY=${builtwith_api_key}&LOOKUP=${domain}" >> "${tmp_dir}/builtwith_subdomain_output.json"
        echo "Done!"
    fi
}

builtwith-src
