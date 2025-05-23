#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * shodan-src                                            #
#                                                           #
#############################################################            

shodan-src(){
    if [ "${shodan_use}" == "yes" ]; then
        echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing shodan... " | tee -a "${log_execution_file}"
        echo -e "\nshodan search --no-color --fields hostnames hostname:${domain}" >> "${log_execution_file}"
        shodan search --no-color --fields hostnames hostname:"${domain}" \
            > "${tmp_dir}/shodan_output.txt" \
            2>> "${log_execution_file}"
        echo "Done!"
        sleep 1
    fi
}

shodan-src
