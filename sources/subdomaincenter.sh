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
    echo -e "\ncurl ${curl_options[@]} https://api.subdomain.center/?domain=${domain}" >> "${log_execution_file}"
    curl "${curl_options[@]}" "https://api.subdomain.center/?domain=${domain}" -o "${tmp_dir}/subdomaincenter_output.json" 2>> "${log_execution_file}"
    echo "Done!"
    sleep 1
}

subdomaincenter-src
