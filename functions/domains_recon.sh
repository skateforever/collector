domains_recon(){
    if [[ "${only_web_data}" == "yes" ]]; then
        for d in $(ls -1t "${output_dir}/${domain}" | grep -Ev "log$"); do
            if [[ -s "${output_dir}/${domain}/${d}/report/web_data_urls.txt" ]]; then
                recon_dir="${output_dir}/${domain}/${d}"
                break
            fi
        done
        aquatone_files_dir="${recon_dir}/aquatone"
        nmap_dir="${recon_dir}/nmap"
        nuclei_dir="${recon_dir}/nuclei"
        report_dir="${recon_dir}/report"
        shodan_dir="${recon_dir}/shodan"
        tmp_dir="${recon_dir}/tmp"
        web_data_dir="${recon_dir}/web-data"
        web_params_dir="${recon_dir}/web-params"
        web_tech_dir="${recon_dir}/web-tech"
    fi

    echo "Directory structure created and ready to work." | tee -a "${log_execution_file}"

    (# Show the directory structure
    echo "The directory structure you will have to work with, is..."
    echo " "
    echo "${output_dir}/${domain}"
    echo -e " ├── log (${yellow}log dir for collector script execution${reset})"
    echo -e " └── $(basename "${recon_dir}")"
    echo -e "     ├── aquatone (${yellow}aquatone output files${reset})"
    echo -e "     ├── nuclei (${yellow}nuclei execution output files${reset})"
    echo -e "     ├── report (${yellow}adjust function output files${reset})"
    echo -e "     ├── tmp (${yellow}subdomains recon tmp files${reset})"
    echo -e "     ├── web-data (${yellow}web data function for gobuster and dirsearch output${reset})"
    echo -e "     ├── web-params (${yellow}web data function for katana and waybackurl output${reset})"
    echo -e "     └── web-tech (${yellow}web data function for response headers using curl or httpx output${reset})"
    echo " "
    echo -e "${red}Attention:${reset} The output from all tools used here will be placed in background and treated later."
    echo -e "\t   If you need look the output in execution time, you need to \"tail\" the files."
    echo " "
    # Execute all functions
    echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} ${green}Recon started on${reset} ${yellow}${domain}${reset}${green}!${reset}"
    if [ "${only_web_data}" == "no" ]; then
        subdomains_recon
        joining_removing_duplicates
        diff_domains
        if [ -s "${report_dir}/domains_diff.txt" ]; then
            managing_the_files "${report_dir}/domains_diff.txt"
        else
            managing_the_files "${report_dir}/domains_found.txt"
        fi
        infra_recon
        shodan_recon
        webapp_alive
        #emails_recon
        if [ "${only_recon}" == "yes" ]; then
            message "${domain}" finished
            exit 0
        fi
    fi
    if [ "${only_web_data}" == "yes" ] && [ ! -s "${report_dir}/web_data_urls.txt" ]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} ${red}The recon finished 'cause an error:${reset}"
        echo -e "\t\t    You haven't the actual ${yellow}web_data_urls.txt${reset} file to collect data to analyze!"
        echo -e "\t\t    Please, run the collector with -d domain --recon or just -d domain to run recon and web data!"
        exit 1
    else
        web_data "${report_dir}/web_data_urls.txt"
        robots_txt
        web_data "${report_dir}/robots_urls.txt"
        for file in "${report_dir}/web_data_urls.txt" "${report_dir}/robots_urls.txt" ; do
            aquatone_function "${file}"
        done
        git_rebuild
    fi
    #report
    message "${domain}") finished 2>> "${log_execution_file}" | tee -a "${log_execution_file}"
}

url_execution(){
    echo "Directory structure created and ready to work." | tee -a "${log_execution_file}"

    (# Show the directory structure
    echo "The directory structure you will have to work with, is..."
    echo " "
    echo "${output_dir}/${url_domain}"
    echo -e " ├── log (${yellow}log dir for collector script execution${reset})"
    echo -e " └── $(basename "${recon_dir}")"
    echo -e "     └── ${url_base} (${yellow}specific directory for the files referring to the tested url${reset})" 
    echo -e "         ├── aquatone-data (${yellow}aquatone output files${reset})"
    echo -e "         └── report (${yellow}adjust function output files${reset})"
    echo " "
    echo -e "${red}Attention:${reset} The output from all tools used here will be placed in background and treated later."
    echo -e "\t   If you need look the output in execution time, you need to \"tail\" the files."
    echo " "
    # Executing just the functions necessary to url check
    echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} ${green}Recon started on${reset} ${yellow}${url_base}${reset}${green}!${reset}"
    web_data "${recon_dir}/url_2_test.txt"
    robots_txt
    web_data "${report_dir}/robots_urls.txt"
    for file in "${recon_dir}/url_2_test.txt" "${report_dir}/robots_urls.txt" ; do
        aquatone_function "${file}"
    done
    git_rebuild 
    message "${url_2_verify}" finished
    rm "${recon_dir}/url_2_test.txt" > /dev/null 2>&1) 2>> "${log_execution_file}"| tee -a "${log_execution_file}"
}

# Checking the runtime parameter dependency for domain recon
check_parameter_dependency_domain(){
    [[ "${args_count}" -gt 9 ]] && echo -e "You are trying to pass a number of parameters beyond what is necessary for this collector reconnaissance option \"${yellow}-d|--domain${reset}\".\n" && usage
    if [[ ${#web_port_detect[@]} -eq 0 ]]; then
        echo -e "You need to specify at least one of these options sort (-ws|--web-short-detection) or long (-wl|--web-long-detection) web detection!\n"
        usage
    fi

    if [[ -z "${web_tool_detection}" ]]; then
        echo -e "You need to inform one of these tools ${bold}${yellow}curl${reset}${normal} or ${bold}${yellow}httpx${reset}${normal} to perform web application detection.\n"
        usage
    fi
}

if [[ -n ${domain} ]] && [[ ! -s "${domain_list}" ]] && [[ -z "${url_2_verify}" ]]; then
    echo "The reconnaissance for ${domain} started at $(date +"%Y%m%d %H:%M")" | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
    clear > "$(tty)"
    echo -e "${collector_command_line}\n"
    check_parameter_dependency_domain
    check_is_known_target "${domain}"
    create_initial_directories_structure
    domain_execution
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
            domain_execution
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

    url_execution
fi
