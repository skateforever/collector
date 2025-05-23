#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * commoncrawl-src                                       #
#                                                           #
#############################################################            

commoncrawl-src(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing commoncrawl... " | tee -a "${log_execution_file}"
    echo -e "\ncurl ${curl_options[@]} \"${commoncrawl_db}?url=*.${domain}/&output=json\" | jq -r .url?" >> "${log_execution_file}"
    commoncrawl_db=$(curl "${curl_options}" "${commoncrawl_url}" | jq --raw-output .[0]'."cdx-api"' 2>> "${log_execution_file}")
    curl "${curl_options}" "${commoncrawl_db}?url=*.${domain}/&output=json" > "${tmp_dir}/commoncrawl_output.json" 2>> "${log_execution_file}"
    echo "Done!"
    sleep 1
}

commoncrawl-src
