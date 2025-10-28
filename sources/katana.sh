#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * katana-src                                            #
#                                                           #
#############################################################            

katana-src(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing katana... "
    echo -e "\n katana ${katana_options[@]} -u ${domain}" >> "${log_execution_file}"
    katana "${katana_options[@]}" -u "${domain}" > "${tmp_dir}/katana_output.tmp" 2>> "${log_execution_file}"
    echo "Done!"
    sleep 1
}

katana-src
