#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * grayhatwarfare-src                                    #
#                                                           #
#############################################################

grayhatwarfare-src(){
    [[ -z "${grayhatwarfare_api_key}" ]] && return 0
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing grayhatwarfare... "
    unset user_agent
    user_agent="$(get_user_agent)"
    echo -e "\ncurl ${curl_options[@]} -H \"Authorization: Bearer ${grayhatwarfare_api_key}\" -H \"User-agent: ${user_agent}\" \"https://buckets.grayhatwarfare.com/api/v2/buckets?keywords=${domain}&limit=100\"" >> "${log_execution_file}"
    curl "${curl_options[@]}" \
        -H "Authorization: Bearer ${grayhatwarfare_api_key}" \
        -H "User-agent: ${user_agent}" \
        "https://buckets.grayhatwarfare.com/api/v2/buckets?keywords=${domain}&limit=100" > "${tmp_dir}/grayhatwarfare_output.json" 2>> "${log_execution_file}"
    echo "Done!"
    sleep 1
}

grayhatwarfare-src
