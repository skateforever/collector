#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * web_data                                              #
#   * robots_txt                                            #
#   * aquatone_function                                     #
#                                                           #
############################################################# 

web_data(){
    target="$1"
    urls_file="$2"
    if [ "$#" != 2 ] && [ ! -s "${urls_file}" ]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Please, especify just 1 file to get URL from."
        echo -e "Please, especify just 1 file to get URL from." | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
        message "${target}" failed
        exit 1
    else
        if [ -s "${urls_file}" ]; then
            if [ -d "${report_dir}" ] && [ -d "${nuclei_dir}" ] && [ -d "${web_data_dir}" ] && [ -d "${web_params_dir}" ] && [ -d "${web_tech_dir}" ] ; then
                echo -e "${red}Warning:${reset} It can take a long time to execute the web_data function!"
                echo -e "\t We have $(wc -l "${urls_file}" | awk '{print $1}') urls to scan and ${#web_wordlists[@]} wordlist(s) to run."
                echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Getting information about urls from response... "
                httpx -no-color -silent -update > /dev/null 2>&1
                while IFS= read -r url; do
                    name="$(echo "${url}" | sed -e "s/http:\/\//http_/" -e "s/https:\/\//https_/" -e "s/:/_/" -e "s/\/$//" -e "s/\//_/g")"
                    file_tech_by_headers="${name}.tech"
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
                        curl ${curl_options[@]} -I "${url}" >> "${web_tech_dir}/${file_tech_by_headers}" 2>> "${log_execution_file}"
                    fi
                    if [ "${web_tool_detection}" == "httpx" ]; then
                        echo "echo ${url} | httpx -silent -no-color -title -status-code -tech-detect -follow-redirects -timeout 3" >> "${log_execution_file}"
                        echo "${url}" | httpx -silent -no-color -title -status-code -tech-detect -follow-redirects -timeout 3 >> "${web_tech_dir}/${file_tech_by_headers}" 2>> "${log_execution_file}"
                    fi
                    unset file_tech_by_headers
                    unset name
                    unset url
                done < "${urls_file}"
                unalias curl > /dev/null 2>&1
                unalias httpx > /dev/null 2>&1
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
                                file_gobuster="${name}.gobuster.${index}"
                                file_dirsearch="${name}.dirsearch.${index}"
                                if [ -n "${use_proxy}" ] && [ "${use_proxy}" == "yes" ]; then
                                    echo "dirsearch -t \"${dirsearch_threads}\" -e \"${web_extensions}\" --random-agent --no-color --quiet-mode \
                                        -w \"${list}\" --proxy \"${proxy_ip}\" --timeout=20 -u \"${url}\"" 2>> "${log_execution_file}"
                                    dirsearch -t "${dirsearch_threads}" -e "${web_extensions}" --random-agent --no-color --quiet-mode \
                                        -w "${list}" --proxy "${proxy_ip}" --timeout=20 \
                                        -u "${url}" >> "${web_data_dir}/${file_dirsearch}" 2>> "${log_execution_file}" &
                                    echo "gobuster dir --quiet --no-color --no-error -z -k -e --timeout 20s --delay 300ms \
                                        --proxy http://${proxy_ip} -t ${gobuster_threads} \
                                        -u ${url} -w ${list} -x ${web_extensions} >> ${web_data_dir}/${file_gobuster}" 2>> "${log_execution_file}"
                                    gobuster dir --quiet --no-color --no-error -z -k -e --timeout 20s --delay 300ms \
                                        --proxy "http://${proxy_ip}" -t "${gobuster_threads}" \
                                        -u "${url}" -w "${list}" -x "${web_extensions}" \
                                        >> "${web_data_dir}/${file_gobuster}" 2>> "${log_execution_file}" &
                                else
                                    echo "dirsearch -t \"${dirsearch_threads}\" -e \"${web_extensions}\" --random-agent \
                                        --no-color --quiet-mode -w \"${list}\" -u \"${url}\"" >> "${log_execution_file}"
                                    dirsearch -t "${dirsearch_threads}" -e "${web_extensions}" --random-agent --no-color --quiet-mode \
                                        -w "${list}" -u "${url}" >> "${web_data_dir}/${file_dirsearch}" 2>> "${log_execution_file}" &
                                    echo "gobuster dir --quiet --no-color --no-error -z -k -e --timeout 20s --delay 300ms \
                                        -t ${gobuster_threads} -u ${url} -w ${list} -x ${web_extensions} \
                                        >> ${web_data_dir}/${file_gobuster}" 2>> "${log_execution_file}"
                                    gobuster dir --quiet --no-color --no-error -z -k -e --timeout 20s --delay 300ms \
                                        -t "${gobuster_threads}" -u "${url}" -w "${list}" -x "${web_extensions}" \
                                        >> "${web_data_dir}/${file_gobuster}" 2>> "${log_execution_file}" &
                                fi
                                while [[ "$(pgrep -acf "[d]irsearch.*${target}$|[g]obuster.*${target}$")" -ge "${web_data_total_processes}" ]]; do
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
                    while pgrep -af "[d]irsearch.*${target}$" > /dev/null || pgrep -af "[g]obuster.*${target}$" > /dev/null; do
                        sleep 1
                    done
                    echo "Done!"

                    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Cleaning up dirsearch files... "
                    sed -i -e 's/.\[4.m//g' -e 's/.\[3.m//g' -e 's/.\[1K.\[0G/\n/g'\
                        -e 's/.\[1m//g' -e 's/.\[0m//g'-e '/Last request to/d' "${web_data_dir}/*.dirsearch*" 2> /dev/null
                    #sed -i -e '/^$/d' "${file}" 2> /dev/null
                    echo "Done!"

                    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Cleaning up gobuster files... "
                    sed -i "s/^..\[2K//" "${web_data_dir}/*.gobuster*" 2> /dev/null
                    echo "Done!"

                    # Notifying the finds
                    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Sending files search notification... "
                    grep --color=never -Ehr "^\[.*\] 200 -" "${web_data_dir}/" | awk '{print $6}' | grep -E "($(echo ${web_extensions} | sed 's/,/|/g'))$" | notify -nc -silent -id "${notify_files_channel}"
                    grep --color=never -Ehr "\(Status: 200\)" "${web_data_dir}/" | awk '{print $1}' | grep -E "($(echo ${web_extensions} | sed 's/,/|/g'))$" | notify -nc -silent -id "${notify_files_channel}"
                    echo "Done!"
                else
                    echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Array of wordlists is empty. Stopping the script!"
                    echo -e "Array of wordlists is empty. Stopping the script!" | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
                    message "${target}" failed
                    exit 1
                fi

                echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing params crawler with wayback and katana... "
                while IFS= read -r url; do
                    name=$(echo "${url}" | sed -e "s/http:\/\//http_/" -e "s/https:\/\//https_/" -e "s/:/_/" -e "s/\/$//" -e "s/\//_/g")
                    file="${name}.params"
                    echo "echo ${url} | waybackurls >> ${web_params_dir}/${file}" >> "${log_execution_file}"
                    echo "${url}" | waybackurls >> "${web_params_dir}/${file}" 2>> "${log_execution_file}"
                    echo "echo ${url} | katana -silent -nc -timeout ${katana_timeout} -c ${katana_threads} -p ${katana_threads} -f qurl -d 10 | grep -E \"^http\" | sort -u >> ${web_params_dir}/${file}" >> "${log_execution_file}"
                    echo "${url}" | katana -silent -nc -timeout "${katana_timeout}" -c ${katana_threads} -p ${katana_threads} -f qurl -d 10 | grep -E "^http" | sort -u >> "${web_params_dir}/${file}" 2>> "${log_execution_file}"
                    #katana -silent -nc -timeout "${katana_timeout}" -c ${katana_threads} -p ${katana_threads} -jc
                    #katana -silent -nc -timeout "${katana_timeout}" -c ${katana_threads} -p ${katana_threads} -f qpath -d 10
                    #www.example.com/path/arquivo.js
                    #www.example.com/path/
                    #www.example.com/path/1/
                    #www.example.com/path/2/
                    #www.example.com/path/3/
                    unset file
                done < "${urls_file}"
                unset url
                echo "Done!"

                # TODO: Put gospider to get more params

                echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing nuclei scan... "
                nuclei -no-color -silent -update > /dev/null 2>&1
                nuclei -no-color -silent -update-templates > /dev/null 2>&1
                while IFS= read -r url; do
                    if [ -n "${use_proxy}" ] && [ "${use_proxy}" == "yes" ]; then
                        echo "echo ${url} | nuclei -no-color -silent -ept ${nuclei_exclude_types} -et ${nuclei_exclude_templates} \
                            -c ${nuclei_threads} -proxy-url \"http://${proxy_ip}\" \
                            -H \"User-Agent: ${nuclei_agent}\"" >> "${log_execution_file}"
                        echo "${url}" | nuclei -no-color -silent -ept "${nuclei_exclude_types}" -et "${nuclei_exclude_templates}" \
                            -c ${nuclei_threads} -proxy-url "http://${proxy_ip}" \
                            -H "User-Agent: ${nuclei_agent}" >> "${nuclei_scan_file}" 2>> "${log_execution_file}" &
                    else
                        echo "echo ${url} | nuclei -no-color -silent -c ${nuclei_threads} -ept ${nuclei_exclude_types} \
                            -et ${nuclei_exclude_templates}" >> "${log_execution_file}"
                        echo "${url}" | nuclei -no-color -silent -ept "${nuclei_exclude_types}" -et "${nuclei_exclude_templates}" \
                            -c ${nuclei_threads} >> "${nuclei_scan_file}" 2>> "${log_execution_file}" &
                    fi
                    while [[ "$(pgrep -acf "[n]uclei")" -ge "${web_data_total_processes}" ]]; do
                        sleep 1
                    done
                done < "${urls_file}"
                echo "Done!"

                # Notifying the finds
                echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Sending nuclei scan notification... "
                grep -Ehr "\[critical\]" "${nuclei_scan_file}" | notify -nc -silent -id "${notify_critical_channel}"
                grep -Ehr "\[high\]" "${nuclei_scan_file}" | notify -nc -silent -id "${notify_high_channel}"
                echo "Done!"

            else
                echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Make sure the directories structure was created. Stopping the script!"
                unset urls_file
                echo -e "Make sure the directories structure was created. Stopping the script!" | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
                message "${target}" failed
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
