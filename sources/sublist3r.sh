#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * sublist3r-src                                         #
#                                                           #
#############################################################

sublist3r-src(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing sublist3r... "
    local sublist3r_out="${tmp_dir}/sublist3r_output.tmp"
    : > "${sublist3r_out}"
    # sublist3r is non-interactive: -o writes one subdomain per line, -n
    # disables colors so the output file is clean for downstream parsing.
    echo -e "\nsublist3r -d ${domain} -n -o ${sublist3r_out}" >> "${log_execution_file}"
    sublist3r -d "${domain}" -n -o "${sublist3r_out}" >> "${log_execution_file}" 2>&1
    echo "Done!"
    sleep 1
}

sublist3r-src
