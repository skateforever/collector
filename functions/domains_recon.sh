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
        joining_subdomains
        diff_domains
        if [ -s "${report_dir}/domains_diff.txt" ]; then
            organizing_subdomains "${report_dir}/domains_diff.txt"
        else
            organizing_subdomains "${report_dir}/domains_found.txt"
        fi
        #infra_recon
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
    message "${domain}" finished) 2>> "${log_execution_file}" | tee -a "${log_execution_file}"
}
