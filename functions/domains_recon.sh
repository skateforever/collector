#!/bin/bash
#############################################################
# The domain recon execution file                           #
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * domains_recon                                         #
#                                                           #
############################################################# 

domains_recon(){
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
    message "${domain}" start
    if [ "${only_web_data}" == "no" ]; then
        subdomains_recon
        joining_subdomains
        diff_domains
        if [ -s "${report_dir}/domains_diff.txt" ]; then
            organizing_subdomains "${report_dir}/domains_diff.txt"
        else
            organizing_subdomains "${report_dir}/domains_found.txt"
        fi
        infra_data
        shodan_recon
        webapp_alive
        #emails_recon
        if [ "${only_recon}" == "yes" ]; then
            message "${domain}" finished
            exit 0
        fi
    fi
    if [ "${only_web_data}" == "yes" ] && [ ! -s "${report_dir}/web_data_urls.txt" ]; then
        message "${domain}" failed
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} ${red}The recon finished 'cause an error:${reset}"
        echo -e "\t\t    You haven't the actual ${yellow}web_data_urls.txt${reset} file to collect data to analyze!"
        echo -e "\t\t    Please, run the collector with -d domain --recon or just -d domain to run recon and web data!"
        exit 1
    else
        web_data "${domain}" "${report_dir}/web_data_urls.txt"
        robots_txt
        web_data "${report_dir}/robots_urls.txt"
        for file in "${report_dir}/web_data_urls.txt" "${report_dir}/robots_urls.txt" ; do
            aquatone_function "${file}"
        done
        git_rebuild
        message "${domain}" finished
    fi) 2>> "${log_execution_file}" | tee -a "${log_execution_file}"
}
