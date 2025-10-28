#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * tlsx-src                                              #
#                                                           #
#############################################################            

tlsx-src(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing tlsx... "
    echo -e "\n tlsx ${tlsx_options[@]} -d ${domain}" >> "${log_execution_file}"
    tlsx "${tlsx_options[@]}" -d "${domain}" > "${tmp_dir}/tlsx_output.json" 2>> "${log_execution_file}"
    echo "Done!"
    sleep 1
}

tlsx-src
