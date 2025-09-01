#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * rapiddns-src                                          #
#                                                           #
#############################################################            

rapiddns-src(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing rapiddns... " | tee -a "${log_execution_file}"
    echo -e "\ncurl ${curl_options[@]} \"https://rapiddns.io/subdomain/${domain}#result\"" >> "${log_execution_file}"
    curl "${curl_options[@]}" "https://rapiddns.io/subdomain/${domain}#result" \
        > "${tmp_dir}/rapiddns_output.txt" \
        2>> "${log_execution_file}"
    echo "Done!"
    sleep 1
}

rapiddns-src
