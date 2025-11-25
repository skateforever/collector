#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * netlas-src                                           #
#                                                           #
#############################################################            

netlas-src(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing netlas... "
    echo -e "\ncurl ${curl_options[@]} https://app.netlas.io/api/domains/?q=*.${domain}" >> "${log_execution_file}"
    curl "${curl_options[@]}" "https://app.netlas.io/api/domains/?q=*.${domain}" -o "${tmp_dir}/netlas_output.json" 2>> "${log_execution_file}"
    echo "Done!"
    sleep 1
}

netlas-src
