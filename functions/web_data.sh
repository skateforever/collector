#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * web_data                                              #
#   * cleanup_web_data_files                                #
#   * robots_txt                                            #
#   * aquatone_function                                     #
#                                                           #
############################################################# 

web_data(){
    if [ $# != 1 ]; then
        echo "Please, especify just 1 file to get URL from."
        exit 1
    else
        urls_file=$1
        if [ -s "${urls_file}" ]; then
            if [ -d "${report_dir}" ] && [ -d "${web_data_dir}" ] && [ -d "${nuclei_dir}" ] && [ -d "${wayback_dir}" ]; then
                echo -e "${red}Warning:${reset} It can take a long time to execute the web_data function!"
                echo -e "\t We have $(wc -l "${urls_file}" | awk '{print $1}') urls to scan and ${#web_wordlists[@]} wordlist(s) to run."
                echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Getting information about urls from response... "
                httpx -no-color -silent -update > /dev/null 2>&1
                while IFS= read -r url; do
                    name="$(echo "${url}" | sed -e "s/http:\/\//http_/" -e "s/https:\/\//https_/" -e "s/:/_/" -e "s/\/$//" -e "s/\//_/g")"
                    file_header_response="${name}_headers_response.txt"
                    > "${web_data_dir}/${file_header_response}"
                    if [ -n "${use_proxy}" ] && [ "${use_proxy}" == "yes" ]; then
                        if [ "${web_tool_detection}" == "curl" ]; then
                            alias curl="curl --proxy ${proxy_ip}"
                        fi
                        if [ "${web_tool_detection}" == "httpx" ]; then
                            alias httpx="httpx -http-proxy ${proxy_ip}"
                        fi
                    fi
                    if [ "${web_tool_detection}" == "curl" ]; then
                        echo "curl ${curl_options[@]} -I ${url}" >> "${log_execution_file}"
                        curl ${curl_options[@]} -I "${url}" >> "${web_data_dir}/${file_header_response}" 2>> "${log_execution_file}"
                    fi
                    if [ "${web_tool_detection}" == "httpx" ]; then
                        echo "echo ${url} | httpx -silent -no-color -title -status-code -tech-detect -follow-redirects -timeout 3" >> "${log_execution_file}"
                        echo "${url}" | httpx -silent -no-color -title -status-code -tech-detect -follow-redirects -timeout 3 >> "${web_data_dir}/${file_header_response}" 2>> "${log_execution_file}"
                    fi
                    unset file_header_response
                    unset name
                    unset url
                done < "${urls_file}"
                unalias curl > /dev/null 2>&1
                unalias httpx > /dev/null 2>&1
                echo "Done!"

                echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing nuclei... "
                nuclei -no-color -silent -update > /dev/null 2>&1
                nuclei -no-color -silent -update-templates > /dev/null 2>&1
                while IFS= read -r url; do
                    name="$(echo "${url}" | sed -e "s/http:\/\//http_/" -e "s/https:\/\//https_/" -e "s/:/_/" -e "s/\/$//" -e "s/\//_/g")"
                    file_nuclei="${name}_nuclei.txt"
                    > "${nuclei_dir}/${file_nuclei}"
                    if [ -n "${use_proxy}" ] && [ "${use_proxy}" == "yes" ]; then
                        if [ ! -f "${nuclei_dir}/${file_nuclei}" ]; then
                            echo "echo ${url} | nuclei -no-color -silent -proxy-url \"http://${proxy_ip}\" -H \"User-Agent: ${nuclei_agent}\" -t \"${nuclei_templates_dir}\"" >> "${log_execution_file}"
                            echo "${url}" | nuclei -no-color -silent -proxy-url "http://${proxy_ip}" -H "User-Agent: ${nuclei_agent}" -t "${nuclei_templates_dir}" \
                            >> "${nuclei_dir}/${file_nuclei}" 2>> "${log_execution_file}" &
                        fi
                    else
                        if [ ! -f "${nuclei_dir}/${file_nuclei}" ]; then
                            echo "echo ${url} | nuclei -no-color -silent -t ${nuclei_templates_dir}" >> "${log_execution_file}"
                            echo "${url}" | nuclei -no-color -silent -t "${nuclei_templates_dir}" >> "${nuclei_dir}/${file_nuclei}" 2>> "${log_execution_file}" &
                        fi
                    fi
                    while [[ "$(pgrep -acf "[n]uclei")" -ge "${web_data_total_processes}" ]]; do
                        sleep 1
                    done
                    unset file_nuclei
                    unset name
                done < "${urls_file}"
                echo "Done!"

                if [ ${#web_wordlists[@]} -gt 0 ]; then
                    echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Web data function will use ${#web_wordlists[@]} wordlists with gobuster and dirsearch... "
                    for list in "${web_wordlists[@]}"; do
                        index=$(printf "%s\n" "${web_wordlists[@]}" | grep -En "^""${list}""$" | awk -F":" '{print $1}')
                        urls_tested=1
                        if [ -s "${list}" ]; then
                            while IFS= read -r url; do
                                # Mounting the file names
                                name="$(echo "${url}" | sed -e "s/http:\/\//http_/" -e "s/https:\/\//https_/" -e "s/:/_/" -e "s/\/$//" -e "s/\//_/g")"
                                file_gobuster="${name}_gobuster_${index}.txt"
                                file_dirsearch="${name}_dirsearch_${index}.txt"
                                if [ -n "${use_proxy}" ] && [ "${use_proxy}" == "yes" ]; then
                                    # Skipping the specific wordlist from dirsearch on gobuster
                                    if grep -E "\.\%EXT\%|\.\%EX\%" "${list}" > /dev/null 2>&1 ; then
                                        echo "dirsearch -t \"${dirsearch_threads}\" -e \"${web_extensions}\" --random-agent --no-color --quiet-mode \
                                            -w \"${list}\" --proxy \"${proxy_ip}\" --timeout=20 -u ${url}" >> "${log_execution_file}"
                                        dirsearch -t "${dirsearch_threads}" -e "${web_extensions}" --random-agent --no-color --quiet-mode \
                                            -w "${list}" --proxy "${proxy_ip}" --timeout=20 \
                                            -u "${url}" >> "${web_data_dir}/${file_dirsearch}" 2>> "${log_execution_file}" &
                                    else
                                        echo "dirsearch -t \"${dirsearch_threads}\" -e \"${web_extensions}\" --random-agent --no-color --quiet-mode \
                                            -w \"${list}\" --proxy \"${proxy_ip}\" --timeout=20 -u \"${url}\"" >> "${log_execution_file}"
                                        echo "${gobuster_bin} dir -z -t \"${gobuster_threads}\" --timeout 20s -x \"${web_extensions}\" \
                                            --proxy \"http://${proxy_ip}\" -k -w \"${list}\" -u \"${url}\"" >> "${log_execution_file}"
                                        dirsearch -t "${dirsearch_threads}" -e "${web_extensions}" --random-agent --no-color --quiet-mode \
                                            -w "${list}" --proxy "${proxy_ip}" --timeout=20 \
                                            -u "${url}" >> "${web_data_dir}/${file_dirsearch}" 2>> "${log_execution_file}" &
                                        ${gobuster_bin} dir -z -t "${gobuster_threads}" --timeout 20s -x "${web_extensions}" \
                                            --proxy "http://${proxy_ip}" -k -w "${list}" -u "${url}" \
                                            >> "${web_data_dir}/${file_gobuster}" 2>> "${log_execution_file}" &
                                    fi
                                else
                                    # Skipping the specific wordlist from dirsearch on gobuster
                                    if grep -E "\.\%EXT\%|\.\%EX\%" "${list}" > /dev/null 2>&1 ; then
                                        echo "dirsearch -t \"${dirsearch_threads}\" -e \"${web_extensions}\" --random-agent --no-color --quiet-mode \
                                            -w \"${list}\" -u \"${url}\"" >> "${log_execution_file}"
                                        dirsearch -t "${dirsearch_threads}" -e "${web_extensions}" --random-agent --no-color --quiet-mode \
                                            -w "${list}" -u "${url}" >> "${web_data_dir}/${file_dirsearch}" 2>> "${log_execution_file}" &
                                    else
                                        echo "dirsearch -t \"${dirsearch_threads}\" -e \"${web_extensions}\" --random-agent --no-color --quiet-mode \
                                            -w \"${list}\" -u \"${url}\"" >> "${log_execution_file}"
                                        echo "${gobuster_bin} dir --delay 300ms -k -z -t \"${gobuster_threads}\" -x \"${web_extensions}\" -w \"${list}\" \
                                            -u \"${url}\"" >> "${log_execution_file}"
                                        dirsearch -t "${dirsearch_threads}" -e "${web_extensions}" --random-agent --no-color --quiet-mode \
                                            -w "${list}" -u "${url}" >> "${web_data_dir}/${file_dirsearch}" 2>> "${log_execution_file}" &
                                        ${gobuster_bin} dir --delay 300ms -k -z -t "${gobuster_threads}" -x "${web_extensions}" -w "${list}" \
                                            -u "${url}" >> "${web_data_dir}/${file_gobuster}" 2>> "${log_execution_file}" &
                                    fi
                                fi
                                while [[ "$(pgrep -acf "[d]irsearch.*${process_domain}|[g]obuster.*${process_domain}")" -ge "${web_data_total_processes}" ]]; do
                                    sleep 1
                                done
                                [[ "${limit_urls}" -eq "${urls_tested}" ]] && break
                                (( urls_tested+=1 ))
                                unset file_dirsearch
                                unset file_gobuster
                                unset name
                                unset url
                            done < "${urls_file}"
                        else
                            echo -e "\t\t    ${red}Error:${reset} ${list} does not exist or is empty!"
                            continue
                        fi
                        unset index
                        unset list
                        unset urls_tested
                    done
                    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Waiting the dirsearch and/or gobuster finish... "
                    while pgrep -af "[d]irsearch.*${process_domain}" > /dev/null || pgrep -af "[g]obuster.*${process_domain}" > /dev/null; do
                        sleep 1
                    done
                    echo "Done!"
                else
                    echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} dirseach/goboster web_data function error: array of wordlists is empty. Stopping the script"
                    exit 1
                fi
                
                echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing wayback... "
                while IFS= read -r url; do
                    name=$(echo "${url}" | sed -e "s/http:\/\//http_/" -e "s/https:\/\//https_/" -e "s/:/_/" -e "s/\/$//" -e "s/\//_/g")
                    file="wayback_${name}.txt"
                    echo "echo ${url} | waybackurls" >> "${log_execution_file}"
                    echo "${url}" | waybackurls > "${wayback_dir}/${file}" 2>> "${log_execution_file}"
                    unset file
                done < "${urls_file}"
                unset url
                echo "Done!"
            else
                echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Make sure the directories structure was created. Stopping the script."
                unset urls_file
                exit 1
            fi
        else
            echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Make sure the ${urls_file} exist and isn't empty."
            unset urls_file
        fi
        unset urls_file
    fi
    echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Web data function is done!"
}

cleanup_web_data_files(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Cleaning up dirsearch files... "
    for file in $(ls -1A "${web_data_dir}" | grep dirsearch); do 
        sed -i -e 's/.\[4.m//g' -e 's/.\[3.m//g' -e 's/.\[1K.\[0G/\n/g' "${web_data_dir}/${file}" 2> /dev/null
        sed -i -e 's/.\[1m//g' -e 's/.\[0m//g' "${web_data_dir}/${file}" 2> /dev/null
        sed -i -e '/Last request to/d' "${web_data_dir}/${file}" 2> /dev/null
        #sed -i -e '/^$/d' "${file}" 2> /dev/null
    done 
    echo "Done!"
    unset file
    unset files
       
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Cleaning up gobuster files... "
    for file in $(ls -1A "${web_data_dir}" | grep gobuster); do
        sed -i "s/^..\[2K//" "${web_data_dir}/${file}" 2> /dev/null
    done 
    echo "Done!"
    unset file
    unset files
}

robots_txt(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Looking for new URLs on robots.txt... "
    for file in $(ls -1A "${web_data_dir}/"); do
        if grep robots.txt "${web_data_dir}/${file}" > /dev/null && [ -s "${file}" ] ; then
            echo "aqui"
            target=$(grep -E "Target:|Url:" "${file}" | sed -e 's/^\[+\] //' | awk '{print $2}' | sed -e 's/\/$//') 
            for url in $(curl -A "${curl_agent}" -s "${target}"/robots.txt | grep -Ev "User-agent: *" | awk '{print $2}' | sed -e "/^\/$/d"); do
                echo "${target}${url}" >> "${report_dir}/robots_urls.txt"
                sed -i -e 's/\r//g' -e 's/\/$//g' "${report_dir}/robots_urls.txt"
            done
        fi
        unset target
        unset file
    done 
    echo "Done!"
    unset files
}

aquatone_function(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Starting aquatone scan... "
    file=$1
    if [ -s "${file}" ]; then
        if [[ -n "${domain}" && -z "${url_2_verify}" ]]; then
            aquatone_log="${tmp_dir}/aquatone_${domain}.log"
        elif [[ -n "${url_2_verify}" && -z "${domain}" ]] ; then
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
                echo -e "\t\t    Please, look what got wrong and run the script again. Stopping the script!"
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
