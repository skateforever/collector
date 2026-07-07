#!/bin/bash
###############################################################################
# This function will try to idenfiy any web application running on subdomain  #
#                                                                             #
# This file is an essential part of collector's execution!                    #
# And is responsible to get the functions:                                    #
#                                                                             #
#   * get_user_agent                                                          #
#   * webapp_alive                                                            #
#   * aquatone_screeshot                                                      #
#                                                                             #
############################################################################### 

get_user_agent(){
    local user_agent_file="${collector_user_agents}"
    # Strip blank lines and # comments before sampling so the wordlist
    # can carry section headers like "# === Desktop ===" without ever
    # producing them as a chosen UA.
    grep -Ev '^[[:space:]]*(#|$)' "${user_agent_file}" | shuf -n 1
}

webapp_alive(){
    local target="$1"
    local alive_file="$2"
    local subdomain port url line http_status_code https_status_code user_agent batch
    echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Initializing the web application discovery and this might take a certain time!"
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Testing subdomains to know if it has a web application... "
    echo -e "\n" >> "${log_execution_file}"
    if [ -s "${alive_file}" ]; then

        # Build explicit proxy arg arrays. The previous approach of `alias curl=`
        # / `alias httpx=` was a no-op: bash does not expand aliases in
        # non-interactive scripts (and `shopt -s expand_aliases` is never set),
        # so --proxy was silently dropped from every call below (report B-04).
        local -a curl_proxy_args=() httpx_proxy_args=()
        if [ -n "${use_proxy}" ] && [ "${use_proxy}" == "yes" ]; then
            curl_proxy_args=(--proxy "${proxy_ip}")
            httpx_proxy_args=(-http-proxy "${proxy_ip}")
        fi

        while IFS= read -r subdomain; do
            [[ -z "${subdomain}" ]] && continue
            user_agent="$(get_user_agent)"
            local batch=0
            for port in "${webapp_port_detect[@]}"; do
                (
                    # Per-worker unique temp file (using subshell PID)
                    local worker_tmp="${tmp_dir}/webapp_urls_$$.tmp"

                    echo "curl ${curl_options_fast[*]} ${curl_proxy_args[*]} -H \"User-agent: ${user_agent}\" -L -w \"%{response_code}\n\" \"http://${subdomain}:${port}\" -o /dev/null" >> "${log_execution_file}"
                    http_status_code=$(curl "${curl_options_fast[@]}" "${curl_proxy_args[@]}" -H "User-agent: ${user_agent}" -L -w "%{response_code}\n" "http://${subdomain}:${port}" -o /dev/null 2>> "${log_execution_file}")
                    local http_curl_exit=$?

                    # Only add if curl succeeded (exit 0) AND HTTP status is valid
                    if [[ "${http_curl_exit}" -eq 0 ]] && [[ "${http_status_code}" =~ ^[1-5][0-9]{2}$ ]]; then
                        echo "http://${subdomain}:${port}" >> "${worker_tmp}"
                    elif [[ "${http_curl_exit}" -ne 0 ]]; then
                        echo "curl failed for http://${subdomain}:${port} (exit code: ${http_curl_exit})" >> "${log_execution_file}"
                    fi

                    echo "curl ${curl_options_fast[*]} ${curl_proxy_args[*]} -H \"User-agent: ${user_agent}\" -L -w \"%{response_code}\n\" \"https://${subdomain}:${port}\" -o /dev/null" >> "${log_execution_file}"
                    https_status_code=$(curl "${curl_options_fast[@]}" "${curl_proxy_args[@]}" -H "User-agent: ${user_agent}" -L -w "%{response_code}\n" "https://${subdomain}:${port}" -o /dev/null 2>> "${log_execution_file}")
                    local https_curl_exit=$?

                    # Only add if curl succeeded (exit 0) AND HTTP status is valid
                    if [[ "${https_curl_exit}" -eq 0 ]] && [[ "${https_status_code}" =~ ^[1-5][0-9]{2}$ ]]; then
                        echo "https://${subdomain}:${port}" >> "${worker_tmp}"
                    elif [[ "${https_curl_exit}" -ne 0 ]]; then
                        echo "curl failed for https://${subdomain}:${port} (exit code: ${https_curl_exit})" >> "${log_execution_file}"
                    fi
                ) &
                ((batch += 1))
                if [[ "${batch}" -ge 20 ]]; then
                    wait
                    batch=0
                fi
            done
            wait
        done < "${report_dir}/domains_alive.txt"

        # Merge seguro: todos os workers terminaram, agora consolidar
        cat "${tmp_dir}"/webapp_urls_*.tmp 2>/dev/null | sort -u > "${tmp_dir}/webapp_urls.tmp"
        rm -f "${tmp_dir}"/webapp_urls_*.tmp

        echo "httpx "${httpx_options[@]}" ${httpx_proxy_args[*]} -p $(echo "${webapp_port_detect[@]}" | sed 's/ /,/g') -l ${report_dir}/domains_alive.txt >> ${tmp_dir}/webapp_urls.tmp" >> "${log_execution_file}"
        httpx "${httpx_options[@]}" "${httpx_proxy_args[@]}" -p $(echo "${webapp_port_detect[@]}" | sed 's/ /,/g') -l "${report_dir}/domains_alive.txt" >> "${tmp_dir}/webapp_urls.tmp" 2>> "${log_execution_file}"
        sleep 1

        if [ -s "${tmp_dir}/webapp_urls.tmp" ]; then
            echo "Done!"
        else
            echo "Fail!"
            echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Something got wrong while checking the status of URLs!"
            echo -e "Something got wrong while checking the status of URLs!" | notify "${notify_options[@]}" -id "${notify_recon_channel}" > /dev/null 2>&1
            message "${target}" failed
            exit 1
        fi

        if [[ -s "${tmp_dir}/webapp_urls.tmp" ]]; then
            while IFS= read -r url; do
                [[ -z "${url}" ]] && continue
                user_agent="$(get_user_agent)"
                if ! curl "${curl_options[@]}" "${curl_proxy_args[@]}" -H "User-agent: ${user_agent}" "${url}" 2>/dev/null | grep -qiE "${webapp_waf_regex}"; then
                    echo "${url}"
                fi
            done < <(sort -u "${tmp_dir}/webapp_urls.tmp") > "${report_dir}/webapp_urls.txt"
            sed -i -E 's|^(http://.+):80$|\1|; s|^(https://.+):443$|\1|' "${report_dir}/webapp_urls.txt"
            sort -u -o "${report_dir}/webapp_urls.txt" "${report_dir}/webapp_urls.txt"
        fi

        # No unalias needed: we no longer create aliases.

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
                echo -e "Could not create file for infrastructure domains, something went wrong." | notify "${notify_options[@]}" -id "${notify_recon_channel}" > /dev/null 2>&1
                message "${target}" failed
                exit 1
            fi
        else
            echo "Fail!"
            echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} We probably didn't have any webapp application, something is wrong!"
            echo -e "We probably didn't have any webapp application, something is wrong!" | notify "${notify_options[@]}" -id "${notify_recon_channel}" > /dev/null 2>&1
            message "${target}" failed
            exit 1
        fi

        if [ -f "${report_dir}/webapp_urls.txt" ] && [ -f "${report_dir}/domains_infrastructure.txt" ]; then
            echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Probably we have: "
            echo -e "\t\t      * $(awk '{print $1}' "${report_dir}/webapp_urls.txt" | sed -e 's/^http.*\/\/// ; s/:.*$//' | awk -F'/' '{print $1}' | sort -u | wc -l) Web Applications URL(s)."
            echo -e "\t\t      * $(wc -l "${report_dir}/domains_infrastructure.txt" | awk '{print $1}') Infrastructure domain(s)."
            echo -e "Probably we have: \n \
                \t* $(awk '{print $1}' "${report_dir}/webapp_urls.txt" | sed -e 's/^http.*\/\/// ; s/:.*$//' | awk -F'/' '{print $1}' | sort -u | wc -l) Web Applications URL(s).\n \
                \t* $(wc -l "${report_dir}/domains_infrastructure.txt" | awk '{print $1}') Infrastructure domain(s)." \
                | notify "${notify_options[@]}" -id "${notify_recon_channel}" > /dev/null 2>&1
        fi
    else
        echo "Fail!"
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} The ${report_dir}/domains_alive.txt does not exist or is empty."
        echo -e "The ${report_dir}/domains_alive.txt does not exist or is empty." | notify "${notify_options[@]}" -id "${notify_recon_channel}" > /dev/null 2>&1
        message "${target}" failed
        exit 1
    fi
}

aquatone_screenshot(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Starting aquatone screenshot... "
    local target="$1"
    local urls_file="$2"
    if [ -s "${urls_file}" ]; then
        if [ ! -d "${aquatone_files_dir}" ]; then
            if mkdir -p "${aquatone_files_dir}" ; then
                echo "aquatone -chrome-path ${chromium_bin} -out ${aquatone_files_dir} -threads ${aquatone_threads} < ${urls_file}" >> "${log_execution_file}"
                aquatone -chrome-path "${chromium_bin}" -out "${aquatone_files_dir}" -threads "${aquatone_threads}" < "${urls_file}" >> "${aquatone_log}" 2>> "${log_execution_file}"
                echo "Done!"
            else
                echo "Fail!"
                echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Something got wrong, wasnt possible create directory ${aquatone_files_dir}."
                echo -e "Something got wrong, wasnt possible create directory ${aquatone_files_dir}.\n\tPlease, look what got wrong and run the script again. Stopping the script!" | notify "${notify_options[@]}" -id "${notify_recon_channel}" > /dev/null 2>&1
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
        echo -e "Make sure the ${urls_file} exist and isn't empty." | notify "${notify_options[@]}" -id "${notify_recon_channel}" > /dev/null 2>&1
        message "${target}" failed
        exit 1
    fi
    echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Finish aquatone screenshot!"
    echo -e "Finish aquatone screenshot!" | notify "${notify_options[@]}" -id "${notify_recon_channel}" > /dev/null 2>&1
}
