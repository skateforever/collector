#!/bin/bash
#############################################################
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * robtex-src                                            #
#                                                           #
#############################################################

robtex-src(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing hackerone... "
    echo -e "\ncurl "https://freeapi.robtex.com/pdns/forward/${domain}" -o ${tmp_dir}/robtex_output.json" >> "${log_execution_file}"
    curl "${curl_options[@]}" "https://freeapi.robtex.com/pdns/forward/${domain}" -o "${tmp_dir}/robtex_output.json" 2>> "${log_execution_file}"
    echo "Done!"
}

robtex-src
