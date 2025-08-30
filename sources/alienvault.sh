#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * alienvault-src                                        #
#                                                           #
#############################################################            

alienvault-src(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing alienvault... " | tee -a "${log_execution_file}"
    echo -e "\ncurl ${curl_options[@]} \"https://otx.alienvault.com/api/v1/indicators/domain/${domain}/passive_dns\" | jq --raw-output '.passive_dns[]?.hostname'" >> "${log_execution_file}"
    curl "${curl_options[@]}" "https://otx.alienvault.com/api/v1/indicators/domain/${domain}/passive_dns" > "${tmp_dir}/alienvault_output.json" 2>> ${log_execution_file}
    echo "Done!"
    sleep 1
}

alienvault-src
