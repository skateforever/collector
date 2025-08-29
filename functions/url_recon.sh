url_recon(){
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
