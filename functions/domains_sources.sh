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
        source_files=(alienvault.sh amass.sh anubis.sh asn-sweep.sh bevigil.sh bing.sh bruteforce.sh bufferover.sh builtwith.sh \
            c99.sh caa-enum.sh censys.sh certspotter.sh chaos.sh circl.sh commoncrawl.sh crt.sh dns-mining.sh dnsdumpster.sh \
            dnsrepo.sh fofa.sh fullhunt.sh github.sh grayhatwarfare.sh grepapp.sh greynoise.sh hackerone.sh hackertarget.sh \
            hunterhow.sh intelx.sh jldc.sh katana.sh leakix.sh merklemap.sh netcraft.sh netlas.sh ns-brute.sh nsec-walk.sh \
            onyphe.sh ptr-sweep.sh publicwww.sh pulsedive.sh rapiddns.sh robots-sitemap.sh robtex.sh securitytrails.sh shodan.sh \
            srv-enum.sh subdomaincenter.sh subfinder.sh sublist3r.sh threatminer.sh tlsx.sh urlfinder.sh urlhaus.sh urlscan.sh \
            virustotal.sh waybackurls.sh webarchive.sh whoisxmlapi.sh zonetransfer.sh)
        for src in "${source_files[@]}"; do
            source "${collector_path}/sources/${src}"
        done
    else
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Make sure the directories structure was created. Stopping the script!"
        echo -e "Make sure the directories structure was created. Stopping the script!" | notify "${notify_pc_args[@]}" "${notify_options[@]}" -id "${notify_recon_channel}" > /dev/null 2>&1
        message "${domain}" failed
        exit 1
    fi
}
