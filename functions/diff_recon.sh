#!/bin/bash
#############################################################
# Getting the difference between old and new files          #
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * diff_domains                                          #
#                                                           #
############################################################# 

diff_domains(){
    if [ -d "${report_dir}" ]; then 
        echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Getting the difference between files to improve the time running collector script... "
        if [ -s "${report_dir}/domains_found.txt" ]; then
            oldest_domains=$(find "${output_dir}/${domain}" -name domains_found.txt -type f | sort -u | grep -v "${date_recon}" | tail -n1)
            if [[ -n "${oldest_domains}" ]]; then
                if cmp -s "${oldest_domains}" "${report_dir}/domains_found.txt"; then
                    echo "Done!"
                    echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} The files are same since last execution of collector!"
                    echo -e "\t Stopping the script!"
                    exit 1
                else
                    diff -y "${oldest_domains}" "${report_dir}/domains_found.txt" | grep ">" | awk '{print $2}' >> "${report_dir}/domains_diff.txt" 2> /dev/null
                    echo "Done!"
                fi
            else
                echo "Done!"
                echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} It looks like it's the collector's first run in this domain!"
            fi
        else
            echo "Fail!"
            echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} File ${report_dir}/domains_alive.txt does not exist or is empty!"
            echo "The error occurred in the function diff_domains.sh!" | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
            echo -e "The message was: \n\tFile ${report_dir}/domains_alive.txt does not exist or is empty!" | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
            message "${domain}" failed
            exit 1
        fi
    else
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Make sure the directories structure was created. Stopping the script."
        echo "The error occurred in the function diff_domains.sh!" | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
        echo -e "The message was: \n\tMake sure the directories structure was created. Stopping the script." | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
        message "${domain}" failed
        exit 1
    fi
}
