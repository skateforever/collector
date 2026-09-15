#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * bing-src                                              #
#                                                           #
#############################################################

bing-src(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing bing... "
    unset user_agent
    : > "${tmp_dir}/bing_output.txt"
    bing_templates=(
        "https://www.bing.com/search?q=site%3A${domain}&form=DEEPSH&shm=cr&shajax=2"
        "https://www.bing.com/search?q=site%3A${domain}&shm=cr&form=DEEPSH&shajax=1"
        "https://www.bing.com/search?q=site%3A${domain}&filt=rf&first=1&FORM=PERE"
        "https://www.bing.com/search?q=site%3A${domain}&filt=rf&first=11&FORM=PERE"
        "https://www.bing.com/search?q=site%3A${domain}&filt=rf&first=21&FORM=PERE"
        "https://www.bing.com/search?q=site%3A${domain}&filt=rf&first=31&FORM=PERE"
        "https://www.bing.com/search?q=site%3A${domain}&filt=rf&first=41&FORM=PERE"
        "https://www.bing.com/search?q=site%3A${domain}&filt=rf&first=51&FORM=PERE"
    )
    for bing_url in "${bing_templates[@]}"; do
        user_agent="$(get_user_agent)"
        echo -e "\ncurl ${curl_options[@]} -L -H \"User-agent: ${user_agent}\" -H \"Accept-Language: en-US,en;q=0.9\" \"${bing_url}\"" >> "${log_execution_file}"
        curl "${curl_options[@]}" -L \
            -H "User-agent: ${user_agent}" \
            -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
            -H "Accept-Language: en-US,en;q=0.9" \
            -H "Referer: https://www.bing.com/" \
            "${bing_url}" >> "${tmp_dir}/bing_output.txt" 2>> "${log_execution_file}"
        sleep 2
    done
    echo "Done!"
}

bing-src
