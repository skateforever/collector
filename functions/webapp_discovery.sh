#!/bin/bash
###############################################################################
# This function will try to idenfiy any web application running on subdomain  #
#                                                                             #
# This file is an essential part of collector's execution!                    #
# And is responsible to get the functions:                                    #
#                                                                             #
#   * webapp_alive                                                            #
#   * aquatone_screeshot                                                      #
#                                                                             #
############################################################################### 

webapp_alive(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Testing subdomains to know if it has a web application... "
    if [ -s "${report_dir}/domains_alive.txt" ]; then

        if [ -n "${proxy_ip}" ] && [ "${proxy_ip}" == "yes" ]; then
            alias curl="curl --proxy ${proxy_ip}"
            alias httpx="httpx -http-proxy ${proxy_ip}"
        fi
        
        for subdomain in $(cat "${report_dir}/domains_alive.txt"); do
            for port in "${webapp_port_detect[@]}"; do
                echo "curl ${curl_options[@]} -L -w \"%{response_code}\n\" \"http://${subdomain}:${port}\" -o /dev/null" >> "${log_execution_file}"
                http_status_code=$(curl "${curl_options[@]}" -L -w "%{response_code}\n" "http://${subdomain}:${port}" -o /dev/null 2>> "${log_execution_file}")
                [[ "${http_status_code}" =~ ^[1-5][0-9]{2}$ ]] && \
                    echo "http://${subdomain}:${port}" >> "${tmp_dir}/webapp_urls.tmp" 2>> "${log_execution_file}"
                echo "curl ${curl_options[@]} -L -w \"%{response_code}\n\" \"https://${subdomain}:${port}\" -o /dev/null" >> "${log_execution_file}"
                https_status_code=$(curl "${curl_options[@]}" -L -w "%{response_code}\n" "https://${subdomain}:${port}" -o /dev/null 2>> "${log_execution_file}")
                [[ "${http_status_code}" =~ ^[1-5][0-9]{2}$ ]] && \
                    echo "https://${subdomain}:${port}" >> "${tmp_dir}/webapp_urls.tmp" 2>> "${log_execution_file}"
            done
            sleep 1
        done

        echo "httpx "${httpx_options[@]}" -p $(echo "${webapp_port_detect[@]}" | sed 's/ /,/g') -l ${report_dir}/domains_alive.txt >> ${tmp_dir}/webapp_urls.tmp" >> "${log_execution_file}"
        httpx "${httpx_options[@]}" -p $(echo "${webapp_port_detect[@]}" | sed 's/ /,/g') -l "${report_dir}/domains_alive.txt" >> "${tmp_dir}/webapp_urls.tmp" 2>> "${log_execution_file}"
        sleep 1

        if [ -s "${tmp_dir}/webapp_urls.tmp" ]; then
            echo "Done!"
        else
            echo "Fail!"
            echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Something got wrong while checking the status of URLs!"
            echo -e "Something got wrong while checking the status of URLs!" | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
            message "${domain}" failed
            exit 1
        fi

        if [[ -s "${tmp_dir}/webapp_urls.tmp" ]]; then
            for url in $(cat "${tmp_dir}/webapp_urls.tmp"); do
                tmp_file=$(mktemp)
                curl "${curl_options[@]}" "$url" 2>/dev/null > "${tmp_file}"
                content="$(cat ${tmp_file})"
                #content_length=${#content}
                #if [[ ${content_length} -lt 50 ]] || ! echo "${content}" | grep -qiE "<html|<body|<title|<!DOCTYPE"; then
                    if ! echo "${content}" | grep -qiE "${webapp_waf_regex}" > /dev/null 2>&1; then
		                echo ${url}
                    fi
                #fi
                rm -f ${tmp_file}
            done | sort -u > "${report_dir}/webapp_urls.txt"
        fi

        unalias curl > /dev/null 2>&1
        unalias httpx > /dev/null 2>&1

        echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Separating infrastructure from web application... "
        if [ -s "${report_dir}/webapp_urls.txt" ]; then
            if cp "${report_dir}/domains_alive.txt" "${report_dir}/domains_infrastructure.txt"; then
                while IFS= read -r line; do
                    subdomain=$(echo "${line}" | sed -e "s/http:\/\///" -e "s/https:\/\///" | awk -F":" '{print $1}' | awk -F"/" '{print $1}')
                    if grep -q "${subdomain}" "${report_dir}/domains_infrastructure.txt" 2>> "${log_execution_file}" ; then
                        sed -i "/^${subdomain}$/d" "${report_dir}/domains_infrastructure.txt"
                    else
                        continue
                    fi
                    unset subdomain
                done < "${report_dir}/webapp_urls.txt"
                echo "Done!"
            else
                echo "Fail!"
                echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Could not create file for infrastructure domains, something went wrong."
                echo -e "Could not create file for infrastructure domains, something went wrong." | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
                message "${domain}" failed
                exit 1
            fi
        else
            echo "Fail!"
            echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} We probably didn't have any webapp application, something is wrong!"
            echo -e "We probably didn't have any webapp application, something is wrong!" | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
            message "${domain}" failed
            exit 1
        fi

        if [ -f "${report_dir}/webapp_urls.txt" ] && [ -f "${report_dir}/domains_infrastructure.txt" ]; then
            echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Probably we have: "
            echo -e "\t\t      * $(awk '{print $1}' "${report_dir}/webapp_urls.txt" | sed -e 's/^http.*\/\/// ; s/:.*$//' | awk -F'/' '{print $1}' | sort -u | wc -l) Web Applications URL(s)."
            echo -e "\t\t      * $(wc -l "${report_dir}/domains_infrastructure.txt" | awk '{print $1}') Infrastructure domain(s)."
            echo -e "Probably we have: \n \
                \t* $(awk '{print $1}' "${report_dir}/webapp_urls.txt" | sed -e 's/^http.*\/\/// ; s/:.*$//' | awk -F'/' '{print $1}' | sort -u | wc -l) Web Applications URL(s).\n \
                \t* $(wc -l "${report_dir}/domains_infrastructure.txt" | awk '{print $1}') Infrastructure domain(s)." \
                | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
        fi
    else
        echo "Fail!"
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} The ${report_dir}/domains_alive.txt does not exist or is empty."
        echo -e "The ${report_dir}/domains_alive.txt does not exist or is empty." | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
        message "${domain}" failed
        exit 1
    fi
}

aquatone_screeshot(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Starting aquatone screenshot... "
    target="$1"
    urls_file="$2"
    if [ -s "${urls_file}" ]; then
        if [ ! -d "${aquatone_files_dir}" ]; then
            if mkdir -p "${aquatone_files_dir}" ; then
                echo "aquatone -chrome-path ${chromium_bin} -out ${aquatone_files_dir} -threads ${aquatone_threads} < ${urls_file}" >> "${log_execution_file}"
                aquatone -chrome-path "${chromium_bin}" -out "${aquatone_files_dir}" -threads "${aquatone_threads}" < "${urls_file}" >> "${aquatone_log}" 2>> "${log_execution_file}"
                echo "Done!"
            else
                echo "Fail!"
                echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Something got wrong, wasnt possible create directory ${aquatone_files_dir}."
                echo -e "Something got wrong, wasnt possible create directory ${aquatone_files_dir}.\n\tPlease, look what got wrong and run the script again. Stopping the script!" | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
                message "${target}" failed
                exit 1
            fi
        else
            echo "aquatone -chrome-path ${chromium_bin} -out ${aquatone_files_dir} -threads ${aquatone_threads} < ${urls_file}" >> "${log_execution_file}"
            aquatone -chrome-path "${chromium_bin}" -out "${aquatone_files_dir}" -threads "${aquatone_threads}" < "${urls_file}" >> "${aquatone_log}" 2>> "${log_execution_file}"
            echo "Done!"
        fi
    else
        echo "Fail!"
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Make sure the ${urls_file} exist and isn't empty."
        echo -e "Make sure the ${urls_file} exist and isn't empty." | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
        message "${target}" failed
        unset urls_file
        exit 1
    fi
    unset aquatone_log
    unset aquatone_files_dir
    unset urls_file
    echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Finish aquatone screenshot!"
    echo -e "Finish aquatone screenshot!" | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
}
