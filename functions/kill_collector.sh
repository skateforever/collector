#!/bin/bash
#############################################################
# This function will kill the collector execution           #
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * kill_collector                                        #
#                                                           #
############################################################# 

kill_collector(){
    for pid in $(ps aux | grep "${1::1}${1:1}" | awk '{print $2}'); do
        kill -9 "${pid}" > /dev/null 2>&1
    done
    if [[ "${killremove_check}" == "yes" ]]; then
        rm -rf "$(find / -iname "$(find / -iname "$2" -type d -exec ls -1 {} \; 2>/dev/null | grep recon_ | tail -n1)" -type d 2> /dev/null)"
    fi
    exit 0
}
