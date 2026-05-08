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
    
    # ADICIONE ESTA LINHA PARA DEBUG
    echo "DEBUG: Dominio é ${domain} e TMP é ${tmp_dir}" >> "${log_execution_file}"
    
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing amass... "

    amass enum "${amass_options[@]}" -d "${domain}" 2>> "${log_execution_file}"
    amass enum "${amass_options[@]}" -passive -d "${domain}" 2>> "${log_execution_file}"
    sleep 3
    amass subs -names -d "${domain}" > "${tmp_dir}/amass_active_output.txt" 2>> "${log_execution_file}"
    cp "${tmp_dir}/amass_active_output.txt" "${tmp_dir}/amass_passive_output.txt"
    
    echo "Done!"
    sleep 1
}

amass-src