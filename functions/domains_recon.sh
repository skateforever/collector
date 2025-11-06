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
    echo -e "└── $(basename "${recon_dir}")"
    echo -e "    ├── log (${yellow}log dir for collector script execution${reset})"
    echo -e "    ├── report (${yellow}adjust function output files${reset})"
    echo -e "    │   ├── scan (${yellow}scan dir output files${reset})"
    echo -e "    │   │   ├── nmap (${yellow}nmap executionr output files${reset})"
    echo -e "    │   │   ├── nuclei (${yellow}nuclei execution output files${reset})"
    echo -e "    │   │   └── shodan (${yellow}shodan execution output files${reset})"
    echo -e "    │   └── webapp (${yellow}webapp data dir for output files${reset})"
    echo -e "    │       ├── aquatone (${yellow}aquatone output files${reset})"
    echo -e "    │       ├── enum (${yellow}gobuster and dirsearch output${reset})"
    echo -e "    │       ├── javascript (${yellow}downloaded JS files to seek params and api keys${reset})"
    echo -e "    │       ├── params (${yellow}katana and waybackurl output${reset})"
    echo -e "    │       └── tech (${yellow}response headers for detection technologie using curl or httpx output${reset})"
    echo -e "    └── tmp (${yellow}subdomains recon tmp files${reset})"
    echo " "
    echo -e "${red}Attention:${reset} The output from all tools used here will be placed in background and treated later."
    echo -e "\t   If you need look the output in execution time, you need to \"tail\" the files."
    echo " "
    # Execute all functions
    message "${domain}" start

    if [[ "${only_webapp_enum}" == "no" ]]; then
        subdomains_recon
        joining_subdomains
        diff_domains
        if [[ -s "${report_dir}/domains_diff.txt" ]]; then
            organizing_subdomains "${report_dir}/domains_diff.txt"
        else
            organizing_subdomains "${report_dir}/domains_found.txt"
        fi
        infra_data
        shodan_recon
        if [[ "${webapp_discovery}" == "yes" ]]; then
            webapp_alive
            webapp_tech "${domain}" "${report_dir}/webapp_urls.txt"
        fi
        [[ "${only_recon}" == "yes" ]] && { message "${domain}" finished; exit 0; }
    fi

    if [[ "${only_webapp_enum}" == "yes" ]] && [[ ! -s "${report_dir}/webapp_urls.txt" ]]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Make sure the ${red}${report_dir}/webapp_urls.txt${reset} exist and isn't empty. You probably forgot to add --webapp-discovery option to execute, or really, we have a problem with script execution."
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} You probably forgot to add ${yellow}--webapp-discovery${reset} option to execute, or really, we have a problem with script execution."
        echo -e "Make sure the ${report_dir}/webapp_urls.txt exist and isn't empty. \nYou probably forgot to add --webapp-discovery option to execute, or really, we have a problem with script execution." | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
        message "${domain}" failed
        exit 1
    fi

    if [[ ! -s "${report_dir}/webapp_urls.txt" ]] && [[ "${webapp_discovery}" == "yes" ]]; then
        webapp_alive
        webapp_tech "${domain}" "${report_dir}/webapp_urls.txt"
    fi

    webapp_enum "${domain}" "${report_dir}/webapp_urls.txt"
    robots_txt
    [[ -s "${report_dir}/robots_urls.txt" ]] && webapp_enum "${domain}" "${report_dir}/robots_urls.txt"

    for urls_file in "${report_dir}/webapp_urls.txt" "${report_dir}/robots_urls.txt"; do
        if [[ -s "${urls_file}" ]]; then
            aquatone_screenshot "${domain}" "${urls_file}"
            crawler_js "${domain}" "${report_dir}/webapp_url.txt"
            webapp_scan "${domain}" "${urls_file}"
        fi
    done
    git_rebuild
    message "${domain}" finished) 2>> "${log_execution_file}" | tee -a "${log_execution_file}"
}
