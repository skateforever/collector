#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * certspotter-src                                       #
#                                                           #
#############################################################            

certspotter-src(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing certspotter... " | tee -a "${log_execution_file}"
    echo -e "\ncurl ${curl_options[@]} \"https://api.certspotter.com/v1/issuances?domain=${domain}&include_subdomains=true&expand=dns_names\" | jq -r '.[].dns_names[]'" >> "${log_execution_file}"
    curl "${curl_options[@]}" "https://api.certspotter.com/v1/issuances?domain=${domain}&include_subdomains=true&expand=dns_names" > "${tmp_dir}/certspotter_output.json" 2>> "${log_execution_file}"
    echo "Done!"
    sleep 1
}

certspotter-src
