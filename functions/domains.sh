#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * subdomains_recon                                      #
#                                                           #
#############################################################            

subdomains_recon(){
    if [ -d "${tmp_dir}" ]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Initializing the subdomains discovery and this might take a certain time!" | tee -a "${log_execution_file}"
        # Backing the correct Cursor position
        echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing alienvault... " | tee -a "${log_execution_file}"
        echo -e "\ncurl ${curl_options[@]} \"https://otx.alienvault.com/api/v1/indicators/domain/${domain}/passive_dns\" | jq --raw-output '.passive_dns[]?.hostname'" >> "${log_execution_file}"
        curl "${curl_options[@]}" "https://otx.alienvault.com/api/v1/indicators/domain/${domain}/passive_dns" > "${tmp_dir}/alienvault_output.json" 2>> ${log_execution_file}
        echo "Done!"
        sleep 1
        
        echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing amass... " | tee -a "${log_execution_file}"
        echo -e "\namass enum ${amass_options[@]} -d ${domain}" >> "${log_execution_file}"
        echo "amass enum ${amass_options[@]} -passive -d ${domain}" >> "${log_execution_file}"
        amass enum "${amass_options[@]}" -d "${domain}" -o "${tmp_dir}/amass_active_output.txt" 2>> "${log_execution_file}"
        amass enum "${amass_options[@]}" -passive -d "${domain}" -o "${tmp_dir}/amass_passive_output.txt" 2>> "${log_execution_file}"
        echo "Done!"
        sleep 1

        # Binary Edge was acquired by Coalition and shutdown after that.
        #if [[ -n ${binaryedge_api_url} ]] && [[ -n "${binaryedge_api_key}" ]]; then
        #    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing binaryedge.io... "
        #    echo "curl -ks -w %{http_code} ${binaryedge_api_url}/user/subscription -H 'X-key: ${binaryedge_api_key}'" >> "${log_execution_file}" 
        #    binaryedge_api_check=$(curl -ks -w %{http_code} "${binaryedge_api_url}/user/subscription" -H "X-key: ${binaryedge_api_key}" -o /dev/null)
        #    if [ "${binaryedge_api_check}" -eq 200 ]; then
        #        echo "curl -ks -H \"X-Key:${binaryedge_api_key}\" \"${binaryedge_api_url}/query/domains/subdomain/${domain}\" | jq -r '.events[]?'" >> "${log_execution_file}"
        #        curl -ks -H "X-Key:${binaryedge_api_key}" "${binaryedge_api_url}/query/domains/subdomain/${domain}" | jq -r '.events[]?' 2>> "${log_execution_file}" \
        #            | sort -u >> "${tmp_dir}/binaryedge_output.txt"
        #        echo "Done!"
        #        sleep 1
        #    fi
        #fi

        if [[ -n "${builtwith_api_key}" ]] && [[ -n "${builtwith_api_url}" ]]; then
            echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing builtwith subdomain... " | tee -a "${log_execution_file}"
            echo -e "\ncurl ${curl_options[@]} ${builtwith_api_url}/v21/api.json?KEY=${builtwith_api_key}&LOOKUP=${domain}" >> "${log_execution_file}"
            curl "${curl_options[@]}" "${builtwith_api_url}/v21/api.json?KEY=${builtwith_api_key}&LOOKUP=${domain}" >> "${tmp_dir}/builtwith_subdomain_output.json"
            echo "Done!"
        fi

        # Censys removed the API key from free users and put it only to the most expensive plan.
        #if [[ -n "${censys_api_url}" ]] && [[ -n "${censys_api_id}" ]] && [[ -n "${censys_api_secret}" ]]; then
        #    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing censys.io... " | tee -a "${log_execution_file}"
        #    censys_api_check=$(curl -ks -w %{http_code} -u "${censys_api_id}:${censys_api_secret}" "${censys_api_url}/account" -H 'accept: application/json' -o /dev/null)
        #    if [ "${censys_api_check}" -eq 200 ]; then
        #        echo -e "\ncensys-subdomain-finder.py --censys-api-id ${censys_api_id} --censys-api-secret ${censys_api_secret} ${domain} --output ${tmp_dir}/censys_output.txt" >> "${log_execution_file}"
        #        censys-subdomain-finder.py --censys-api-id "${censys_api_id}" --censys-api-secret "${censys_api_secret}" "${domain}" --output "${tmp_dir}/censys_output.txt" > /dev/null 2>> "${log_execution_file}"
        #        echo "Done!"
        #        sleep 1
        #    fi
        #fi

        echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing certspotter... " | tee -a "${log_execution_file}"
        echo -e "\ncurl -ks \"https://api.certspotter.com/v1/issuances?domain=${domain}&include_subdomains=true&expand=dns_names\" | jq -r '.[].dns_names[]'" >> "${log_execution_file}"
        curl -ks "https://api.certspotter.com/v1/issuances?domain=${domain}&include_subdomains=true&expand=dns_names" >> "${tmp_dir}/certspotter_output.json" 2>> "${log_execution_file}"
        echo "Done!"
        sleep 1

        echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing commoncrawl... " | tee -a "${log_execution_file}"
        echo -e "\ncurl -ks \"${commoncrawl_db}?url=*.${domain}/&output=json\" | jq -r .url?" >> "${log_execution_file}"
        commoncrawl_db=$(curl "${curl_options}" "${commoncrawl_url}" | jq --raw-output .[0]'."cdx-api"' 2>> "${log_execution_file}")
        curl "${curl_options}" "${commoncrawl_db}?url=*.${domain}/&output=json" > "${tmp_dir}/commoncrawl_output.json" 2>> "${log_execution_file}"
        echo "Done!"
        sleep 1

        echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing crt.sh... " | tee -a "${log_execution_file}"
        echo -e "\ncurl -ks \"https://crt.sh/?q=%25.${domain}&output=json\" | jq -r '.[].name_value'" >> "${log_execution_file}"
        curl "${curl_options[@]}" "https://crt.sh/?q=%25.${domain}&output=json" \
            > "${tmp_dir}/crtsh_output.json" \
            2>> "${log_execution_file}"
        echo "Done!"
        sleep 1

        # Now dnsdb.info is paid product owned by domaintools.com
        #if [[ -n "${dnsdb_api_url}" ]] && [[ -n "${dnsdb_api_key}" ]]; then
        #    dnsdb_api_check=$(curl "${curl_options[@]}" -g -w "%{http_code}\n" -H "Accept: application/json" -H "X-API-Key: ${dnsdb_api_key}" "${dnsdb_api_url}/*.${domain}?limit=1000000000" -o /dev/null)
        #    if [ "${dnsdb_api_check}"  -eq 200 ]; then
        #        echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing dnsdb... "
        #        curl "${curl_options[@]}" -g -H "Accept: application/json" -H "X-API-Key: ${dnsdb_api_key}" "${dnsdb_api_url}/*.${domain}?limit=1000000000" \
        #            | jq --raw-output -r .rrname? 2>> ${log_execution_file} \
        #            | sed -e 's/\.$//' \
        #            | sort -u >> "${tmp_dir}/dnsdb_output.txt"
        #        echo "Done!"
        #        echo "curl ${curl_options[@]} -g -H \"Accept: application/json\" -H \"X-API-Key: ${dnsdb_api_key}\" \"${dnsdb_api_url}/*.${domain}?limit=1000000000\" | jq --raw-output -r .rrname? >> "${log_execution_file}"
        #        sleep 1
        #    fi
        #fi

        echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing dns dumpster... " | tee -a "${log_execution_file}"
        echo -e "\ncurl ${curl_options[@]} -H X-API-Key: ${dnsdumpster_api_key} ${dnsdumpster_api_url}/${domain}" >> "${log_execution_file}"
        curl "${curl_options[@]}" -H "X-API-Key: ${dnsdumpster_api_key}" "${dnsdumpster_api_url}/${domain}" \
            > "${tmp_dir}/dnsdumpster_output.json" \
            2>> "${log_execution_file}"
        echo "Done!"
        sleep 1

        echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing hackertarget... " | tee -a "${log_execution_file}"
        echo -e "\ncurl ${curl_options[@]} \"${hackertarget_url}${domain}\"" >> "${log_execution_file}"
        curl "${curl_options[@]}" "${hackertarget_url}${domain}" > "${tmp_dir}/hackertarget_output.txt" 2>> "${log_execution_file}"
        echo "Done!"
        sleep 1

        # netcraft
        # "https://searchdns.netcraft.com/?restriction=site+contains&host=${domain}&position=limited"

        echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing rapiddns... " | tee -a "${log_execution_file}"
        echo -e "\ncurl ${curl_options[@]} \"https://rapiddns.io/subdomain/${domain}#result\"" >> "${log_execution_file}"
        curl "${curl_options[@]}" "https://rapiddns.io/subdomain/${domain}#result" \
            > "${tmp_dir}/rapiddns_output.txt" \
            2>> "${log_execution_file}"
        echo "Done!"
        sleep 1

        # Acquired by M$
        #if [[ -n "${riskiq_api_key}" ]] && [[ -n "${riskiq_api_secret}" ]]; then
        #   echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing riskiq... " \
        #        | tee -a "${log_execution_file}"
        #    riskiq_api_check=$(curl "${curl_options[@]}" -w "%{http_code}\n" -u "${riskiq_api_key}:${riskiq_api_secret}" "${riskiq_api_url}?query=${domain}" -o /dev/null)
        #    if [ "${riskiq_api_check}" -eq 200 ]; then
        #        echo -e "\ncurl ${curl_options[@]} -u \"${riskiq_api_key}:${riskiq_api_secret}\" \"${riskiq_api_url}?que\ry=${domain}\" | jq -r .subdomains[]?" >> "${log_execution_file}"
        #        curl "${curl_options[@]}" -u "${riskiq_api_key}:${riskiq_api_secret}" "${riskiq_api_url}?query=${domain}" \
        #             | jq -r '.subdomains[]?' 2>> "${log_execution_file}" | sort -u | grep -Ev "^.*_domainkey$" >> "${tmp_dir}/riskiq_output.txt"
        #        sed -i "s/$/\.${domain}/" "${tmp_dir}/riskiq_output.txt"
        #        echo "Done!"
        #        sleep 1
        #    fi
        #fi

        if [[ -n "${securitytrails_api_key}" ]]; then
            echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing security trails... " | tee -a "${log_execution_file}"
            echo -e "\ncurl ${curl_options[@]} -H 'Accept: application/json' -H \"APIKEY: ${securitytrails_api_key}\" \
                \"${securitytrails_api_url}/domain/${domain}/subdomains?children_only=false&include_inactive=true\"" \
                >> "${log_execution_file}"
            securitytrails_api_check=$(curl "${curl_options[@]}" "${securitytrails_api_url}/ping" -H "APIKEY: ${securitytrails_api_key}" -H 'Accept: application/json' | jq -r '.success' 2>> ${log_execution_file})
            if [ "${securitytrails_api_check}" == "true" ]; then
                curl "${curl_options[@]}" -H 'Accept: application/json' -H "APIKEY: ${securitytrails_api_key}" \
                    "${securitytrails_api_url}/domain/${domain}/subdomains?children_only=false&include_inactive=true" \
                    > "${tmp_dir}/securitytrails_output.json" 2>> "${log_execution_file}"
                echo "Done!"
                sleep 1
            fi
        fi

        if [ "${shodan_use}" == "yes" ]; then
            echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing shodan... " | tee -a "${log_execution_file}"
            echo -e "\nshodan search --no-color --fields hostnames hostname:${domain}" >> "${log_execution_file}"
            shodan search --no-color --fields hostnames hostname:"${domain}" \
                > "${tmp_dir}/shodan_output.txt" \
                2>> "${log_execution_file}" \
            echo "Done!"
            sleep 1
        fi

        echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing subfinder... " | tee -a "${log_execution_file}"
        echo -e "\n subfinder ${subfinder_options[@]} -d ${domain}" >> "${log_execution_file}"
        subfinder "${subfinder_options[@]}" -d "${domain}" > "${tmp_dir}/subfinder_output.txt" 2>> "${log_execution_file}"
        echo "Done!"
        sleep 1

        # Threatcrowd looks like does not work anymore
        #echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing threatcrowd... "
        #curl "${curl_options[@]}" "${threatcrowd_url}${domain}" | jq -r '.subdomains[]?' 2>> "${log_execution_file}" \
        #    | grep -Eo "\b[A-Za-z0-9.-]+\.[A-Za-z]{2,6}\b" \
        #    | grep -P "${domain}" | sort -u >> "${tmp_dir}/threatcrowd_output.txt"
        #echo "Done!"
        #echo "curl ${curl_options[@]} \"${threatcrowd_url}${domain}\" | jq -r '.subdomains[]?'" >> "${log_execution_file}" 
        #sleep 1

        # Threatminer does not get brazilian domains
        # Threatminer was shutdown
        #echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing threatminer... " | tee -a "${log_execution_file}"
        #echo -e "\ncurl ${curl_options[@]} \"${threatminer_url}${domain}&rt=5\" | jq -r '.results[]?'" >> "${log_execution_file}"
        #curl "${curl_options[@]}" "${threatminer_url}${domain}&rt=5" \
        #   | jq -r '.results[]?' 2>> "${log_execution_file}" | sort -u >> "${tmp_dir}/threatminer_output.txt"
        #echo "Done!"
        #sleep 1

        if [[ -n "${virustotal_api_url}" ]] && [[ -n "${virustotal_api_key}" ]]; then
            echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing virus total... " | tee -a "${log_execution_file}"
            echo -e "\ncurl ${curl_options[@]} -H \"X-Apikey: ${virustotal_api_key}\" \"${virustotal_api_url}/${domain}/subdomains?limit=40\"" >> "${log_execution_file}"
            virustotal_api_check=$(curl "${curl_options[@]}" -w "%{http_code}\n" -H "X-Apikey: ${virustotal_api_key}" "${virustotal_api_url}/${domain}/subdomains?limit=40" -o /dev/null)
            if [ "${virustotal_api_check}" -eq 200 ]; then
                curl "${curl_options[@]}" -H "X-Apikey: ${virustotal_api_key}" "${virustotal_api_url}/${domain}/subdomains?limit=40" \
                    > "${tmp_dir}/virustotal_output.json" 2>> "${log_execution_file}"
                echo "Done!"
                sleep 1
            fi
        fi

        echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing webarchive... " | tee -a "${log_execution_file}"
        echo -e "\ncurl ${curl_options[@]} \"http://web.archive.org/cdx/search/cdx?url=*.${domain}/*&output=text&fl=original&collapse=urlkey\"" >> "${log_execution_file}"
        curl "${curl_options[@]}" "http://web.archive.org/cdx/search/cdx?url=*.${domain}/*&output=text&fl=original&collapse=urlkey" \
            -o "${tmp_dir}/webarchive_output.txt"
        echo "Done!"
        sleep 1

        if [[ -n "${whoisxmlapi_api_key}" ]] && [[ -n "${whoisxmlapi_subdomain_url}" ]]; then
            echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing whoisxmlapi... " | tee -a "${log_execution_file}"
            echo -e "\ncurl ${curl_options[@]} -X POST \"${whoisxmlapi_subdomain_url}\" -H \"Content-Type: application/json\" \
                --data '{\"apiKey\": \"${whoisxmlapi_api_key}\", \"domains\": {\"include\": [\"${domain}\"]},\"subdomains\": {\"include\": [],\"exclude\": []}}' \
                | jq -r '.domainsList[]'" >> "${log_execution_file}"
            curl "${curl_options[@]}" -X POST "${whoisxmlapi_subdomain_url}" -H "Content-Type: application/json" \
                --data '{"apiKey": "'${whoisxmlapi_api_key}'", "domains": {"include": ["'${domain}'"]},"subdomains": {"include": [],"exclude": []}}' \
                -o "${tmp_dir}/whoisxmlapi_output.json" 2>> "${log_execution_file}"
            echo "Done!"
        fi
        sleep 1

        if [ "${#dns_wordlists[@]}" -gt 0 ]; then
            echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} We will execute brute force dns with amass, gobuster and dnssearch ${#dns_wordlists[@]} time(s)." | tee -a "${log_execution_file}"
            echo -e "\t Take a break as this step takes a while." | tee -a "${log_execution_file}"
            
            echo "We will execute brute force dns with amass, gobuster and dnssearch ${#dns_wordlists[@]} time(s)." | tee -a "${log_execution_file}"
            for list in "${dns_wordlists[@]}"; do
                index=$(printf "%s\n" "${dns_wordlists[@]}" | grep -En "^${list}$" | awk -F":" '{print $1}')
                if [ -s "${list}" ]; then
                    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Execution number ${index}... " | tee -a "${log_execution_file}"
                    echo -e "\namass enum -src -w ${list} -d ${domain}" >> "${log_execution_file}" 
                    amass enum -src -w "${list}" -d "${domain}" >> "${tmp_dir}/amass_brute_output_${index}.txt" 2>> "${log_execution_file}"
                    echo -e "\ngobuster dns -z -q -t ${gobuster_threads} -d ${domain} -w ${list}" >> "${log_execution_file}"
                    gobuster dns -z -q -t "${gobuster_threads}" -d "${domain}" -w "${list}" >> "${tmp_dir}/gobuster_dns_output_${index}.txt" 2>> "${log_execution_file}"
                    echo -e "\ndnssearch -consumers 600 -domain ${domain} -wordlist ${list}" >> "${log_execution_file}"
                    dnssearch -consumers 600 -domain "${domain}" -wordlist "${list}" | \
                    grep "${domain}" >> "${tmp_dir}/dnssearch_output_${index}.txt" 2>> "${log_execution_file}"
                    echo "Done!"
                    sleep 1
                else
                    echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Execution number ${index}, error: ${list} does not exist or is empty!"
                    continue
                fi
                unset index
            done
            unset list
            echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Brute force execution of amass, gobuster and dnssearch is done."
        fi
    
        for ns in $(dig +short ns "${domain}" 2> /dev/null | sed -e 's/\.$//'); do
            if ! dig axfr "@${ns}" "${domain}" 2> /dev/null | grep -Ei "Transfer failed.|servers could be reached|timed out.|network unreachable.$" > /dev/null 2>&1; then
                dig axfr "@${ns}" "${domain}" >> "${tmp_dir}/zone_transfer.txt" 2> /dev/null
            fi
        done
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} The Subdomain Discovery is finished!"
    else
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Make sure the directories structure was created. Stopping the script!"
        echo "The error occurred in the function domains.sh!" | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
        echo -e "The message was: \n\tMake sure the directories structure was created. Stopping the script!" | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
        echo "The reconnaissance for ${target} failed at $(date +"%Y%m%d %H:%M")" | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
        exit 1
    fi
}
