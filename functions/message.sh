#!/bin/bash
##################################################################
# This function will display start, finished and failed messages #
#                                                                #
# This file is an essential part of collector's execution!       #
# And is responsible to get the functions:                       #
#                                                                #
#   * message                                                    #
#                                                                # 
################################################################## 

message(){
    local target="$1"
    local status="$2"
    if [ "${status}" == "start" ]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} The reconnaissance on ${yellow}${target}${reset} ${green}started!${reset}"
        echo "The reconnaissance on ${target} started at $(date +"%Y%m%d %H:%M")!" | notify "${notify_options[@]}" -id "${notify_recon_channel}" > /dev/null 2>&1
    fi
    if [ "${status}" == "finished" ]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} The reconnaissance on ${yellow}${target}${reset} ${green}finished!${reset}"
        echo "The reconnaissance on ${target} finished at $(date +"%Y%m%d %H:%M")!" | notify "${notify_options[@]}" -id "${notify_recon_channel}" > /dev/null 2>&1
    fi
    if [ "${status}" == "failed" ]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} The reconnaissance on ${yellow}${target}${reset} ${red}failed!${reset}"
        echo "The reconnaissance on ${yellow}${target}${reset} ${red}failed${reset} at $(date +"%Y%m%d %H:%M")!" | notify "${notify_options[@]}" -id "${notify_recon_channel}" > /dev/null 2>&1
    fi
}
