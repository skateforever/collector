#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * amass-src                                             #
#                                                           #
#############################################################            

amass-src(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing amass... "
    echo -e "\namass enum ${amass_options[@]} -d ${domain}" >> "${log_execution_file}"
    echo "amass enum ${amass_options[@]} -passive -d ${domain}" >> "${log_execution_file}"
    amass enum "${amass_options[@]}" -d "${domain}" -o "${tmp_dir}/amass_active_output.txt" 2>> "${log_execution_file}"
    amass enum "${amass_options[@]}" -passive -d "${domain}" -o "${tmp_dir}/amass_passive_output.txt" 2>> "${log_execution_file}"
    echo "Done!"
    sleep 1
}

amass-src
