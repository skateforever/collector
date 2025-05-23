#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * subfinder-src                                         #
#                                                           #
#############################################################            

subfinder-src(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing subfinder... " | tee -a "${log_execution_file}"
    echo -e "\n subfinder ${subfinder_options[@]} -d ${domain}" >> "${log_execution_file}"
    subfinder "${subfinder_options[@]}" -d "${domain}" > "${tmp_dir}/subfinder_output.txt" 2>> "${log_execution_file}"
    echo "Done!"
    sleep 1
}

subfinder-src
