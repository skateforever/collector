#!/bin/bash
###############################################################################
# This function will try to idenfiy any web application running on subdomain  #
#                                                                             #
# This file is an essential part of collector's execution!                    #
# And is responsible to get the functions:                                    #
#                                                                             #
#   * webapp_alive                                                            #
#   * aquatone_scan                                                           #
#                                                                             #
############################################################################### 

webapp_alive(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Testing subdomains to know if it has a web application... "
    if [ -s "${report_dir}/domains_alive.txt" ]; then

        if [ -n "${proxy_ip}" ] && [ "${proxy_ip}" == "yes" ]; then
            if [ "${webapp_tool_detection}" == "curl" ]; then
                alias curl="curl --proxy ${proxy_ip}"
            fi
            if [ "${webapp_tool_detection}" == "httpx" ]; then
                alias httpx="httpx -http-proxy ${proxy_ip}"
            fi
        fi

        for subdomain in $(cat "${report_dir}/domains_alive.txt"); do
            if [ "${webapp_tool_detection}" == "curl" ]; then
                for port in "${webapp_port_detect[@]}"; do
                    subdomain_http_status_check=$(curl "${curl_options[@]}" -L -w "%{response_code}\n" "http://${subdomain}:${port}" -o /dev/null)
                    subdomain_https_status_check=$(curl "${curl_options[@]}" -L -w "%{response_code}\n" "https://${subdomain}:${port}" -o /dev/null)
                    echo -e "http://${subdomain}:${port}\t${subdomain_http_status_check}" >> "${tmp_dir}/webapp_status_tmp.txt"
                    echo -e "https://${subdomain}:${port}\t${subdomain_https_status_check}" >> "${tmp_dir}/webapp_status_tmp.txt"
                done
            fi
            if [ "${webapp_tool_detection}" == "httpx" ]; then
                echo "${subdomain}" | httpx -nc -silent -p $(echo "${webapp_port_detect[@]}" | sed 's/ /,/g') -status-code | \
                    sed 's/\[// ; s/]//' >> "${tmp_dir}/webapp_status_tmp.txt"
            fi
        done

        echo "acabou"
        exit 1

        if [ -s "${tmp_dir}/webapp_status_tmp.txt" ]; then
            echo "Done!"
            sed -i 's/\/\/$// ; s/:443// ; s/:80$// ; s/:80\t/\t/ ; s/\(:80\)\(\/\)/\2/ ; s/:\/$// ; s/\(\.\)\([[:alpha:]]*\)\(\/$\)/\1\2/' "${tmp_dir}/webapp_status_tmp.txt"

            echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Getting domain names for web applications... "
            for page_status in "${webapp_get_status[@]}"; do
                if [[ "${page_status}" =~ "30" ]]; then
                    for url_redirected in $(grep -E "${page_status}$" "${tmp_dir}/webapp_status_tmp.txt" | awk '{print $1}'); do
                        curl "${curl_options[@]}" -L -o /dev/null -w "%{url_effective}\n" "${url_redirected}"
                    done
                fi
                grep -E "${page_status}$" "${tmp_dir}/webapp_status_tmp.txt" | awk '{print $1}'
            #done | sed -E 's/^http(|s):\/\/// ; s/:.*$//' | awk -F'/' '{print $1}' >> "${tmp_dir}/webapp_status_tmp.txt"
            done | sort -u >> "${report_dir}/statu" "${tmp_dir}/webapp_status_tmp.txt"
            unset url_redirected

            if [ -s "${tmp_dir}/webapp_status_tmp.txt" ]; then
                sort -u -o "${report_dir}/webapp_status.txt" "${tmp_dir}/webapp_status_tmp.txt"
                echo "Done!"
            else
                echo "Fail!"
                echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Something got wrong while checking web status file!"
                echo "Something got wrong while checking web status file!" | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
                message "${domain}" failed
                exit 1
            fi
        else
            echo "Fail!"
            echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Something got wrong while checking the status of URLs!"
            echo -e "Something got wrong while checking the status of URLs!" | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
            message "${domain}" failed
            exit 1
        fi

        if [ -s "${report_dir}/webapp_status.txt" ]; then
            echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Separating web applications according to the HTTP Status Code defined in collector.cfg... "
            grep -E "$(echo "${webapp_get_status[@]}" | tr -s ' ' '|')" "${report_dir}/webapp_status.txt" | awk '{print $1}' >> "${report_dir}/webapp_urls.txt"
            grep -Ev "$(echo "${webapp_get_status[@]}" | tr -s ' ' '|')" "${report_dir}/webapp_status.txt" | awk '{print $1}' >> "${report_dir}/api_urls.txt"
            echo "Done!"
        fi

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
            echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} We probably didn't have any application with HTTP Status Code defined in collector.cfg, something is wrong!"
            echo -e "We probably didn't have any application with HTTP Status Code defined in collector.cfg, something is wrong!" | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
            message "${domain}" failed
            exit 1
        fi

        if [ -f "${report_dir}/webapp_urls.txt" ] && [ -f "${report_dir}/domains_infrastructure.txt" ]; then
            echo -e "\t\t    Probably we have: "
            echo -e "\t\t      * $(awk '{print $1}' "${report_dir}/webapp_status.txt" | sed -e 's/^http.*\/\/// ; s/:.*$//' | awk -F'/' '{print $1}' | sort -u | wc -l) Web Applications URL(s)."
            echo -e "\t\t      * $(wc -l "${report_dir}/domains_infrastructure.txt" | awk '{print $1}') Infrastructure domain(s)."
            echo -e "Probably we have: \n \
                \t* $(awk '{print $1}' "${report_dir}/webapp_status.txt" | sed -e 's/^http.*\/\/// ; s/:.*$//' | awk -F'/' '{print $1}' | sort -u | wc -l) Web Applications URL(s).\n \
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
    unalias curl > /dev/null 2>&1
    unalias httpx > /dev/null 2>&1
}

aquatone_scan(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Starting aquatone scan... "
    file=$1
    if [ -s "${file}" ]; then
        if [[ -n "${target}" && -z "${url_2_verify}" ]]; then
            aquatone_log="${tmp_dir}/aquatone_${target}.log"
        elif [[ -n "${url_2_verify}" && -z "${target}" ]] ; then
            aquatone_log="${tmp_dir}/aquatone_${url_base}.log"
        fi
        if [ ! -d "${aquatone_files_dir}" ]; then
            if mkdir -p "${aquatone_files_dir}" ; then
                echo "aquatone -chrome-path ${chromium_bin} -out ${aquatone_files_dir} -threads ${aquatone_threads} < ${file}" >> "${log_execution_file}"
                aquatone -chrome-path "${chromium_bin}" -out "${aquatone_files_dir}" -threads "${aquatone_threads}" < "${file}" >> "${aquatone_log}" 2>> "${log_execution_file}"
                echo "Done!"
            else
                echo "Fail!"
                echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Something got wrong, wasnt possible create directory ${aquatone_files_dir}."
                echo -e "Something got wrong, wasnt possible create directory ${aquatone_files_dir}.\n\tPlease, look what got wrong and run the script again. Stopping the script!" | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
                message "${target}" failed
                exit 1
            fi
        else
            echo "aquatone -chrome-path ${chromium_bin} -out ${aquatone_files_dir} -threads ${aquatone_threads} < ${file}" >> "${log_execution_file}"
            aquatone -chrome-path "${chromium_bin}" -out "${aquatone_files_dir}" -threads "${aquatone_threads}" < "${file}" >> "${aquatone_log}" 2>> "${log_execution_file}"
            echo "Done!"
        fi
    else
        echo "Fail!"
        echo -e "\t\t    The ${file} does not exist or is empty!"
    fi
    unset aquatone_log
    unset aquatone_files_dir
    unset file
    echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Finish aquatone scan!"
}
