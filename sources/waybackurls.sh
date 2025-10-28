#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * waybackurls-src                                       #
#                                                           #
#############################################################            

waybackurls-src(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing waybackurls... "
    echo -e "\n echo \"${domain}\" | waybackurls" >> "${log_execution_file}"
    echo "${domain}" | waybackurls > "${tmp_dir}/waybackurls_output.tmp" 2>> "${log_execution_file}"
    echo "Done!"
    sleep 1
}

waybackurls-src
