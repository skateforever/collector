# main function of the collector script

collector_exec(){
    if [[ -n ${domain} ]] && [[ ! -s "${domain_list}" ]] && [[ -z "${url_2_verify}" ]]; then
        check_is_known_target "${domain}"
        create_initial_directories_structure
        domains_recon
    fi
    
    if [[ -z ${domain} ]] && [[ -s "${domain_list}" ]] && [[ -z "${url_2_verify}" ]]; then
        unset domain
        while read -r domain; do 
            check_is_known_target "${domain}"
            create_initial_directories_structure
            if [[ $(host -t A "${domain}" | grep -E "has.address" | awk '{print $4}' | grep -E "${IPv4_regex}$" > /dev/null 2>&1 ; echo $?) -eq 0 ]]; then
                domains_recon
            else
                echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} The ${yellow}${domain}${reset} does not exist!" | tee -a "${log_dir}/domain_doesnot_exit.txt"
                echo "The ${domain} does not exist!" | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
                message "${domain}" failed
            fi
        done < "${domain_list}"
        unset domain
    fi
    
    if [[ -z ${domain} ]] && [[ ! -s "${domain_list}" ]] && [[ -n "${url_2_verify}" ]]; then
        url_domain=$(echo "${url_2_verify}" | sed -e 's/http.*\/\///' | awk -F'/' '{print $1}' | xargs -I {} basename {})
        check_is_known_target "${url_domain}"
        create_initial_directories_structure
        url_recon
    fi
}
