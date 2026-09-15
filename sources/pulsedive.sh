#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * pulsedive-src                                         #
#                                                           #
#############################################################

pulsedive-src(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing pulsedive... "
    unset user_agent
    user_agent="$(get_user_agent)"
    if [[ -n "${pulsedive_api_key}" ]]; then
        echo -e "\ncurl ${curl_options[@]} -H \"User-agent: ${user_agent}\" \"https://pulsedive.com/api/explore.php?q=domain%3D${domain}&limit=1000&pretty=1&key=${pulsedive_api_key}\"" >> "${log_execution_file}"
        curl "${curl_options[@]}" \
            -H "User-agent: ${user_agent}" \
            "https://pulsedive.com/api/explore.php?q=domain%3D${domain}&limit=1000&pretty=1&key=${pulsedive_api_key}" > "${tmp_dir}/pulsedive_output.json" 2>> "${log_execution_file}"
    else
        echo -e "\ncurl ${curl_options[@]} -H \"User-agent: ${user_agent}\" \"https://pulsedive.com/api/explore.php?q=domain%3D${domain}&limit=1000&pretty=1\"" >> "${log_execution_file}"
        curl "${curl_options[@]}" \
            -H "User-agent: ${user_agent}" \
            "https://pulsedive.com/api/explore.php?q=domain%3D${domain}&limit=1000&pretty=1" > "${tmp_dir}/pulsedive_output.json" 2>> "${log_execution_file}"
    fi
    echo "Done!"
    sleep 1
}

pulsedive-src
