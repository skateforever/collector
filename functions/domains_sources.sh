#!/bin/bash

#############################################################
# Load all source files to domains_recon function           #
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * subdomains_recon                                      #
#                                                           #
#############################################################            

subdomains_recon(){
    if [ -d "${tmp_dir}" ]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Initializing the subdomains discovery and this might take a certain time!"
        source_files=(alienvault.sh amass.sh bruteforce.sh builtwith.sh certspotter.sh commoncrawl.sh crt.sh \
            dnsdumpster.sh hackertarget.sh katana.sh netcraft.sh rapiddns.sh securitytrails.sh shodan.sh subfinder.sh \
            tlsx.sh urlfinder.sh urlscan.sh virustotal.sh waybackurls.sh webarchive.sh whoisxmlapi.sh zonetransfer.sh)
        for src in "${source_files[@]}"; do
            source "${collector_path}/sources/${src}"
        done
    else
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Make sure the directories structure was created. Stopping the script!"
        echo -e "Make sure the directories structure was created. Stopping the script!" | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
        message "${domain}" failed
        exit 1
    fi
}
