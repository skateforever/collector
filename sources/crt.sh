#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * crt-src                                               #
#                                                           #
#############################################################            

crt-src(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing crt.sh... "
    echo -e "\ncurl -ks \"https://crt.sh/?q=%25.${domain}&output=json\" | jq -r '.[].name_value'" >> "${log_execution_file}"
    curl "${curl_options[@]}" "https://crt.sh/?q=%25.${domain}&output=json" \
        > "${tmp_dir}/crtsh_output.json" \
        2>> "${log_execution_file}"
    echo "Done!"
    sleep 1
}

crt-src
