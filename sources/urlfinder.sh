#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * urlfinder-src                                         #
#                                                           #
#############################################################            

urlfinder-src(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing urlfinder... "
    echo -e "\n urlfinder ${urlfinder_options[@]} -d ${domain}" >> "${log_execution_file}"
    urlfinder "${urlfinder_options[@]}" -d "${domain}" > "${tmp_dir}/urlfinder_output.tmp" 2>> "${log_execution_file}"
    echo "Done!"
    sleep 1
}

urlfinder-src
