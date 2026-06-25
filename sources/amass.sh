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
    local amass_out="${tmp_dir}/amass_output.tmp"
    : > "${amass_out}"
    # amass v5: output is written directly via -o; 'amass subs' subcommand no longer exists.
    echo -e "\namass enum ${amass_options[*]} -d ${domain} -o ${amass_out}" >> "${log_execution_file}"
    amass enum "${amass_options[@]}" -d "${domain}" -o "${amass_out}" 2>> "${log_execution_file}"
    echo -e "\namass enum ${amass_options[*]} -passive -d ${domain} -o ${amass_out}" >> "${log_execution_file}"
    amass enum "${amass_options[@]}" -passive -d "${domain}" -o "${amass_out}" 2>> "${log_execution_file}"
    echo "Done!"
    sleep 1
}

amass-src
