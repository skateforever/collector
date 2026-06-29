#!/bin/bash
###########################################################################
# Those functions try to get all data as possible from a web application  #
#                                                                         #
# This file is an essential part of collector's execution!                #
# And is responsible to get the functions:                                #
#                                                                         #
#   * acunetix_scan                                                       #
#                                                                         #
# nuclei_scan moved to scans/nuclei.sh.                                   #
###########################################################################

acunetix_scan(){
    target="$1"
    urls_file="$2"
    echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Initializing the web application scan with acunetix and this might take a certain time!"
    echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing acunetix web application vulnerability scan..."
    #if [ "$#" != 2 ] && [ ! -s "${urls_file}" ]; then
    #fi
}
