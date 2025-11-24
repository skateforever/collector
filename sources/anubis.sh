#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * abunis-src                                            #
#                                                           #
#############################################################            

anubis-src(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing abunis... "
    echo -e "\ncurl ${curl_options[@]} https://anubisdb.com/anubis/subdomains/${domain}" >> "${log_execution_file}"
    curl "${curl_options[@]}" "https://anubisdb.com/anubis/subdomains/${domain}" -o "${tmp_dir}/anubis_output.json" 2>> "${log_execution_file}"
    echo "Done!"
    sleep 1
}

anubis-src
