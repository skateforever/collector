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
        echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing builtwith subdomain... "
        echo -e "\ncurl ${curl_options[@]} ${builtwith_api_url}/v21/api.json?KEY=${builtwith_api_key}&LOOKUP=${domain}" >> "${log_execution_file}"
        curl "${curl_options[@]}" "${builtwith_api_url}/v21/api.json?KEY=${builtwith_api_key}&LOOKUP=${domain}" >> "${tmp_dir}/builtwith_subdomain_output.json"
        echo "Done!"
    fi
}

builtwith-src
