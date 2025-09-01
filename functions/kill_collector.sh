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
    exit 0
}
