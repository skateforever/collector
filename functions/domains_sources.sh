#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * subdomains_recon                                      #
#                                                           #
#############################################################            

subdomains_recon(){
    if [ -d "${tmp_dir}" ]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Initializing the subdomains discovery and this might take a certain time!" | tee -a "${log_execution_file}"
        source_files=(alienvault.sh amass.sh bruteforce.sh builtwith.sh certspotter.sh commoncrawl.sh crt.sh \
            dnsdumpster.sh hackertarget.sh netcraft.sh rapiddns.sh securitytrails.sh shodan.sh subfinder.sh \
            tlsx.sh virustotal.sh webarchive.sh whoisxmlapi.sh zonetransfer.sh)
        for src in "${source_files[@]}"; do
            source "${PWD}/sources/${src}"
        done
    else
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Make sure the directories structure was created. Stopping the script!"
        echo "The error occurred in the function domains.sh!" | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
        echo -e "The message was: \n\tMake sure the directories structure was created. Stopping the script!" | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
        echo "The reconnaissance for ${target} failed at $(date +"%Y%m%d %H:%M")" | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
        exit 1
    fi
}
