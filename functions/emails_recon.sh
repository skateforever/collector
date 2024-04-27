#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * emails_recon                                          #
#                                                           #
#############################################################            

emails_recon(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Loooking for emails to help during blackbox pentest... "
    # Hunter.io emails collect
    if [ -n ${hunterio_api} ]; then
        curl -kLs "https://api.hunter.io/v2/domain-search?domain=${domain}&api_key=${hunterio_api}" | jq -M -r '.[].emails'  | grep -E "value" | uniq | grep -v null | tr '\n' ' ' | sed 's/"value"/\n"value"/g ; s/"value": //g ; s/"domain": //g ; s/"//g ; s/,//g' >> "${tmp_dir}/hunterio_emails.txt"
    fi

    

    if [ -n ${lampyre_api_key} ]; then
        curl ${curl_options[@]} "lampyre.io/domain=${domain}&${lampyre_api_key}" >> "${tmp_dir}/lampyre_email.txt" 2>> "${log_execution_file}"
    fi

    #sort -u -o "${report_dir}/emails.txt" "${tmp_dir}/emails.txt"

    #snov_api



    echo "Done!"
    #echo "The error occurred in the function emails_recon.sh!" | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
    #echo -e "The message was: \n\tMake sure the directories structure was created. Stopping the script." |
    #echo "The reconnaissance for ${domain} failed at $(date +"%Y%m%d %H:%M")" | notify -nc -silent -id "${notify_recon_channel}" > /dev/null

}
