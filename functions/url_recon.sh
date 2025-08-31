url_recon(){
    echo "Directory structure created and ready to work." | tee -a "${log_execution_file}"

    url_domain=$(echo "${url_2_verify}" | sed -e 's/http.*\/\///' | awk -F'/' '{print $1}' | xargs -I {} basename {})

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
    [[ -s "${recon_dir}/url_2_test.txt"  ]] && rm "${recon_dir}/url_2_test.txt"
   
    message "${url_domain}" start
    
    if [ $(host -t A "${url_domain}" | grep -v "Host.*not.found:" | awk '{print $4}' | \
            grep -E "^^([0-9]+(\.|$)){4}|^([0-9a-fA-F]{0,4}:){1,7}([0-9a-fA-F]){0,4}$") ]; then
       echo "${url_domain}" > "${recon_dir}/url_2_test.txt"
    else
       message ${url_domain} failed
       exit 1
    fi 

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



        if [[ $(echo "${url_2_verify}" | grep -qE "^(http|https)://" ; echo "$?") -eq 0 ]]; then
            echo "${url_2_verify}" > "${recon_dir}/url_2_test.txt"
        else
            [[ "200" -eq "$(curl -o /dev/null -Ls -w "%{http_code}\n" "http://${url_2_verify}")" ]] && curl -o /dev/null -Ls -w "%{url_effective}\n" "http://${url_2_verify}" > "${recon_dir}/url_2_test.txt"
            [[ "200" -eq "$(curl -o /dev/null -kLs -w "%{http_code}\n" "https://${url_2_verify}")" ]] && curl -o /dev/null -kLs -w "%{url_effective}\n" "https://${url_2_verify}" > "${recon_dir}/url_2_test.txt"
        fi

