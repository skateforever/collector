#!/bin/bash
###########################################################################
# Those functions try to get all data as possible from a web application  #
#                                                                         #
# This file is an essential part of collector's execution!                #
# And is responsible to get the functions:                                #
#                                                                         #
#   * webapp_enum                                                         #
#   * webapp_tech                                                         #
#   * robots_txt                                                          #
#                                                                         #
########################################################################### 

webapp_enum(){
    target="$1"
    urls_file="$2"
    echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing web application files and dirs enumeration..."
    if [ "$#" != 2 ] && [ ! -s "${urls_file}" ]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Please, especify just 1 file to get URL from."
        echo -e "Please, especify just 1 file to get URL from." | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
        message "${target}" failed
        exit 1
    else
        if [ -s "${urls_file}" ]; then
            if [ -d "${report_dir}" ]  && [ -d "${webapp_enum_dir}" ] ; then
                echo -e "${red}Warning:${reset} It can take a long time to execute the enumeration!"
                echo -e "\t We have $(wc -l "${urls_file}" | awk '{print $1}') urls to scan and ${#webapp_wordlists[@]} wordlist(s) to run."

                if [ ${#webapp_wordlists[@]} -gt 0 ]; then
                    echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Web application enumeration will use ${#webapp_wordlists[@]} wordlists with gobuster and dirsearch... "
                    for list in "${webapp_wordlists[@]}"; do
                        index=$(printf "%s\n" "${webapp_wordlists[@]}" | grep -En "^""${list}""$" | awk -F":" '{print $1}')
                        urls_tested=1
                        if [ -s "${list}" ]; then
                            while IFS= read -r url; do
                                # Mounting the file names
                                name="$(echo "${url}" | sed -e "s/http:\/\//http_/" -e "s/https:\/\//https_/" -e "s/:/_/" -e "s/\/$//" -e "s/\//_/g")"
                                file_gobuster="${name}.gobuster.${index}"
                                file_dirsearch="${name}.dirsearch.${index}"
                                if [ -n "${use_proxy}" ] && [ "${use_proxy}" == "yes" ]; then
                                    echo "dirsearch -t \"${dirsearch_threads}\" -e \"${webapp_extensions}\" --random-agent --no-color --quiet-mode \
                                        -w \"${list}\" --proxy \"${proxy_ip}\" --timeout=20 -u \"${url}\"" >> "${log_execution_file}"
                                    dirsearch -t "${dirsearch_threads}" -e "${webapp_extensions}" --random-agent --no-color --quiet-mode \
                                        -w "${list}" --proxy "${proxy_ip}" --timeout=20 \
                                        -u "${url}" >> "${webenum_dir}/${file_dirsearch}" 2>> "${log_execution_file}" &
                                    echo "gobuster dir --quiet --no-color --no-error -z -k -e --timeout 20s --delay 300ms \
                                        --proxy http://${proxy_ip} -t ${gobuster_threads} -u ${url} -w ${list} \
                                        -x ${webapp_extensions} >> ${webenum_dir}/${file_gobuster}" >> "${log_execution_file}"
                                    gobuster dir --quiet --no-color --no-error -z -k -e --timeout 20s --delay 300ms \
                                        --proxy "http://${proxy_ip}" -t "${gobuster_threads}" \
                                        -u "${url}" -w "${list}" -x "${webapp_extensions}" \
                                        >> "${webenum_dir}/${file_gobuster}" 2>> "${log_execution_file}" &
                                else
                                    echo "dirsearch -t \"${dirsearch_threads}\" -e \"${web_extensions}\" --random-agent \
                                        --no-color --quiet-mode -w \"${list}\" -u \"${url}\"" >> "${log_execution_file}"
                                    dirsearch -t "${dirsearch_threads}" -e "${web_extensions}" --random-agent --no-color --quiet-mode \
                                        -w "${list}" -u "${url}" >> "${webenum_dir}/${file_dirsearch}" 2>> "${log_execution_file}" &
                                    echo "gobuster dir --quiet --no-color --no-error -z -k -e --timeout 20s --delay 300ms \
                                        -t ${gobuster_threads} -u ${url} -w ${list} -x ${web_extensions} \
                                        >> ${webenum_dir}/${file_gobuster}" >> "${log_execution_file}"
                                    gobuster dir --quiet --no-color --no-error -z -k -e --timeout 20s --delay 300ms \
                                        -t "${gobuster_threads}" -u "${url}" -w "${list}" -x "${web_extensions}" \
                                        >> "${webenum_dir}/${file_gobuster}" 2>> "${log_execution_file}" &
                                fi
                                while [[ "$(pgrep -acf "[d]irsearch.*${target}$|[g]obuster.*${target}$")" -ge "${webapp_data_total_processes}" ]]; do
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
                            echo -e "Error: ${list} does not exist or is empty!" >> "${log_execution_file}"
                            echo -e "Error: ${list} does not exist or is empty!" | notify -nc -silent -id "${notify_files_channel}" 
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
                        -e 's/.\[1m//g' -e 's/.\[0m//g'-e '/Last request to/d' "${webenum_dir}/*.dirsearch*" 2> /dev/null
                    echo "Done!"

                    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Cleaning up gobuster files... "
                    sed -i "s/^..\[2K//" "${webenum_dir}/*.gobuster*" 2> /dev/null
                    echo "Done!"

                    # Notifying the finds
                    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Sending files search notification... "
                    grep --color=never -Ehr "^\[.*\] 200 -" "${webenum_dir}/" | awk '{print $6}' | grep -E "($(echo ${web_extensions} | sed 's/,/|/g'))$" | notify -nc -silent -id "${notify_files_channel}"
                    grep --color=never -Ehr "\(Status: 200\)" "${webenum_dir}/" | awk '{print $1}' | grep -E "($(echo ${web_extensions} | sed 's/,/|/g'))$" | notify -nc -silent -id "${notify_files_channel}"
                    echo "Done!"
                else
                    echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Array of wordlists is empty. Stopping the script!"
                    echo -e "Array of wordlists is empty. Stopping the script!" | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
                    message "${target}" failed
                    exit 1
                fi
            else
                echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Make sure the directories structure was created. Stopping the script!"
                unset urls_file
                echo -e "Make sure the directories structure was created. Stopping the script!" | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
                message "${target}" failed
                exit 1
            fi
        else
            echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Make sure the ${urls_file} exist and isn't empty."
            echo -e "Make sure the ${urls_file} exist and isn't empty." | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
            message "${target}" failed
            unset urls_file
            exit 1
        fi
        unset urls_file
    fi
    echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Web application enumeration is done!"
}

webapp_tech(){
    target="$1"
    urls_file="$2"
    echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing web application technology enumeration..."
    if [ "$#" != 2 ] && [ ! -s "${urls_file}" ]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Please, especify just 1 file to get URL from."
        echo -e "Please, especify just 1 file to get URL from." | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
        message "${target}" failed
        exit 1
    else
        if [ -s "${urls_file}" ]; then
            if [ -d "${report_dir}" ] && [ -d "${webapp_tech_dir}" ] ; then
                echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Getting information about urls from response... "
                httpx -no-color -silent -update > /dev/null 2>&1
                while IFS= read -r url; do
                    name="$(echo "${url}" | sed -e "s/http:\/\//http_/" -e "s/https:\/\//https_/" -e "s/:/_/" -e "s/\/$//" -e "s/\//_/g")"
                    file_tech_by_headers="${name}.tech"
                    if [ -n "${use_proxy}" ] && [ "${use_proxy}" == "yes" ]; then
                        if [ "${webapp_tool_detection}" == "curl" ]; then
                            alias curl="curl --proxy ${proxy_ip}"
                        fi
                        if [ "${webapp_tool_detection}" == "httpx" ]; then
                            alias httpx="httpx -http-proxy ${proxy_ip}"
                        fi
                    fi
                    if [ "${webapp_tool_detection}" == "curl" ]; then
                        echo "curl ${curl_options[@]} -I ${url}" >> "${log_execution_file}"
                        curl ${curl_options[@]} -I "${url}" >> "${webapp_tech_dir}/${file_tech_by_headers}" 2>> "${log_execution_file}"
                    fi
                    if [ "${webapp_tool_detection}" == "httpx" ]; then
                        echo "echo ${url} | httpx ${httpx_options[@]}" >> "${log_execution_file}"
                        echo "${url}" | httpx "${httpx_options[@]}" >> "${webapp_tech_dir}/${file_tech_by_headers}" 2>> "${log_execution_file}"
                    fi
                    unset file_tech_by_headers
                    unset name
                    unset url
                done < "${urls_file}"
                unalias curl > /dev/null 2>&1
                unalias httpx > /dev/null 2>&1
                echo "Done!"
            fi
        fi
    fi
}

robots_txt(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Looking for new URLs on robots.txt... "
    for file in $(ls -1A "${webenum_dir}/"); do
        if grep robots.txt "${webenum_dir}/${file}" > /dev/null && [ -s "${file}" ] ; then
            target=$(grep -E "Target:|Url:" "${file}" | sed -e 's/^\[+\] //' | awk '{print $2}' | sed -e 's/\/$//') 
            for url in $(curl "${curl_options[@]}" -s "${target}"/robots.txt | grep -Ev "User-agent: *" | awk '{print $2}' | sed -e "/^\/$/d"); do
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
