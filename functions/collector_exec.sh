# main function of the collector script

collector_exec(){
    if [[ -n ${domain} ]] && [[ ! -s "${domain_list}" ]] && [[ -z "${url_2_verify}" ]]; then
        echo "The reconnaissance for ${domain} started at $(date +"%Y%m%d %H:%M")" | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
        clear > "$(tty)"
        echo -e "${collector_command_line}\n"
        check_parameter_dependency_domain
        check_is_known_target "${domain}"
        create_initial_directories_structure
        domains_recon
    fi
    
    if [[ -z ${domain} ]] && [[ -s "${domain_list}" ]] && [[ -z "${url_2_verify}" ]]; then
        unset domain
        while read -r domain; do 
            echo "The reconnaissance for ${domain} started at $(date +"%Y%m%d %H:%M")" | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
            $(clear >&2)
            echo -e "${collector_command_line}\n"
            check_parameter_dependency_domain
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
        # Checking the runtime parameter dependency for url recon
        if [[ -n "${url_2_verify}" && -n "${domain}" ]] || [[ "${#dns_wordlists[*]}" -gt 0 ]] || \
            [[ -n "${url_2_verify}" && -n "${limit_urls}" ]] || [[ -n "${url_2_verify}" && "${#excluded[*]}" -gt 0 ]]; then
                echo -e "You have specified one or more options that are not used with \"-u|--url\"!\n"
                usage
        fi

        if [[ "${args_count}" -gt 4 ]]; then
            echo -e "You are trying to pass a number of parameters beyond what is necessary for this collector reconnaissance option \"${yellow}-u|--url${reset}\".\n"
            usage
        fi
        url_base=$(echo "${url_2_verify}" | sed -e 's/http.*\/\///' | awk -F'/' '{print $1}' | xargs -I {} basename {})
        mapfile -d'.' -t url_tmp_domain <<< "${url_base}"
        for (( i=$((${#url_tmp_domain[@]}-1)); i>=0; i-- ));do
            url_domain=$(echo "${url_tmp_domain[$i]}.${url_domain}" | sed -e 's/\.$//' -e 's/^\.//' -e 's/[[:space:]]*$//')
            [[ $(host -t A "${url_domain}" | grep -v "Host.*not.found:" | awk '{print $4}' | \
                grep -E "^^([0-9]+(\.|$)){4}|^([0-9a-fA-F]{0,4}:){1,7}([0-9a-fA-F]){0,4}$") ]] && break
        done

        echo "The reconnaissance for ${url_base} started at $(date +"%Y%m%d %H:%M")" | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
        clear > "$(tty)"
        echo -e "$0 $*\n"
        check_is_known_target "${url_domain}"
        create_initial_directories_structure

        [[ -s "${recon_dir}/url_2_test.txt"  ]] && rm "${recon_dir}/url_2_test.txt"

        if [[ $(echo "${url_2_verify}" | grep -qE "^(http|https)://" ; echo "$?") -eq 0 ]]; then
            echo "${url_2_verify}" > "${recon_dir}/url_2_test.txt"
        else
            [[ "200" -eq "$(curl -o /dev/null -Ls -w "%{http_code}\n" "http://${url_2_verify}")" ]] && curl -o /dev/null -Ls -w "%{url_effective}\n" "http://${url_2_verify}" > "${recon_dir}/url_2_test.txt"
            [[ "200" -eq "$(curl -o /dev/null -kLs -w "%{http_code}\n" "https://${url_2_verify}")" ]] && curl -o /dev/null -kLs -w "%{url_effective}\n" "https://${url_2_verify}" > "${recon_dir}/url_2_test.txt"
        fi

        url_recon
    fi
}
