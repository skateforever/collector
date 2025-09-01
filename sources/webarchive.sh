#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * webarchive                                            #
#                                                           #
#############################################################            

webarchive-src(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing webarchive... " | tee -a "${log_execution_file}"
    echo -e "\ncurl ${curl_options[@]} \"http://web.archive.org/cdx/search/cdx?url=*.${domain}/*&output=text&fl=original&collapse=urlkey\"" >> "${log_execution_file}"
    curl "${curl_options[@]}" "http://web.archive.org/cdx/search/cdx?url=*.${domain}/*&output=text&fl=original&collapse=urlkey" \
        > "${tmp_dir}/webarchive_output.txt" 2>> "${log_execution_file}" 
    echo "Done!"
    sleep 1
}

webarchive-src
