#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * subdomains_recon                                      #
#   * joining_removing_duplicates                           #
#   * managing_the_files                                    #
#                                                           #
#############################################################            

subdomains_recon(){
    if [ -d "${tmp_dir}" ]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Initializing the subdomains discovery and this might take a certain time!"
        # Backing the correct Cursor position
        echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing alienvault... "
        curl "${curl_options[@]}" "https://otx.alienvault.com/api/v1/indicators/domain/${domain}/passive_dns" \
            | jq --raw-output '.passive_dns[]?.hostname' 2>> ${log_execution_file} | sort -u >> "${tmp_dir}/alienvault_output.txt"
        echo "Done!"
        echo "curl ${curl_options[@]} \"https://otx.alienvault.com/api/v1/indicators/domain/${domain}/passive_dns\" | jq --raw-output '.passive_dns[]?.hostname'" >> "${log_execution_file}"
        sleep 1
        
        echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing amass... "
        timeout $((${amass_timeout_execution} + 1))m amass enum -timeout "${amass_timeout_execution}" -d "${domain}" >> "${tmp_dir}/amass_output.txt" 2>> "${log_execution_file}"
        timeout $((${amass_timeout_execution} + 1))m amass enum -timeout "${amass_timeout_execution}" -passive -d "${domain}" >> "${tmp_dir}/amass_passive_output.txt" 2>> "${log_execution_file}"
        echo "Done!"
        echo "amass enum -timeout ${amass_timeout_execution} -d ${domain}" >> "${log_execution_file}"
        echo "amass enum -timeout ${amass_timeout_execution} -passive -d ${domain}" >> "${log_execution_file}"
        sleep 1

        if [[ -n ${binaryedge_api_url} ]] && [[ -n "${binaryedge_api_key}" ]]; then
            binaryedge_api_check=$(curl -ks -w %{http_code} "${binaryedge_api_url}/user/subscription" -H "X-key: ${binaryedge_api_key}" -o /dev/null)
            if [ "${binaryedge_api_check}" -eq 200 ]; then
                echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing binaryedge.io... "
                curl -ks -H "X-Key:${binaryedge_api_key}" "${binaryedge_api_url}/query/domains/subdomain/${domain}" | jq -r '.events[]?' 2>> "${log_execution_file}" \
                    | sort -u >> "${tmp_dir}/binaryedge_output.txt"
                echo "Done!"
                echo "curl -ks -H \"X-Key:${binaryedge_api_key}\" \"${binaryedge_api_url}/query/domains/subdomain/${domain}\" | jq -r '.events[]?'" >> "${log_execution_file}"
                sleep 1
            fi
        fi

        if [[ -n "${builtwith_api_key}" ]] && [[ -n "${builtwith_api_url}" ]]; then
            echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing builtwith subdomain... "
            curl "${curl_options[@]}" "${builtwith_api_url}/v21/api.json?KEY=${builtwith_api_key}&LOOKUP=${domain}" \
                | jq -r '.Results[].Result.Paths[].SubDomain' | sort -u | sed "s/$/\.${domain}/g" >> "${tmp_dir}/builtwith_subdomain__output.txt"

            curl "${curl_options[@]}" "${builtwith_api_url}/tag1/api.json?KEY=${builtwith_api_key}&LOOKUP=IP-$(dig +short ${domain} A | head -n1)" | \
                jq -r '.Identifers[].Matches[].Domain' >> "${report_dir}/shared_cloud.txt"
            echo "Done!"
            echo "curl ${curl_options[@]} ${builtwith_api_url}/v21/api.json?KEY=${builtwith_api_key}&LOOKUP=${domain}" >> "${log_execution_file}"
            echo "curl ${curl_options[@]} ${builtwith_api_url}/tag1/api.json?KEY=${builtwith_api_key}&LOOKUP=IP-$(dig +short ${domain} A | head -n1)" >> "${log_execution_file}"
        fi

        if [[ -n "${censys_api_url}" ]] && [[ -n "${censys_api_id}" ]] && [[ -n "${censys_api_secret}" ]]; then
            censys_api_check=$(curl -ks -w %{http_code} -u "${censys_api_id}:${censys_api_secret}" "${censys_api_url}/account" -H 'accept: application/json' -o /dev/null)
            if [ "${censys_api_check}" -eq 200 ]; then
                echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing censys.io... "
                censys-subdomain-finder.py --censys-api-id "${censys_api_id}" --censys-api-secret "${censys_api_secret}" "${domain}" --output "${tmp_dir}/censys_output.txt" > /dev/null 2>> "${log_execution_file}"
                echo "Done!"
                echo "censys-subdomain-finder.py --censys-api-id ${censys_api_id} --censys-api-secret ${censys_api_secret} ${domain} --output ${tmp_dir}/censys_output.txt" >> "${log_execution_file}"
                sleep 1
            fi
        fi

        echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing certspotter... "
        curl -ks "https://api.certspotter.com/v1/issuances?domain=${domain}&include_subdomains=true&expand=dns_names" \
            | jq -r '.[].dns_names[]' 2>> ${log_execution_file} | sed 's/\"//g' | sed 's/\*\.//g' \
            | sort -u | grep "${domain}" >> "${tmp_dir}/certspotter_output.txt"
        echo "Done!"
        echo "curl -ks \"https://api.certspotter.com/v1/issuances?domain=${domain}&include_subdomains=true&expand=dns_names\" | jq -r '.[].dns_names[]'" >> "${log_execution_file}"
        sleep 1

        echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing commoncrawl... "
        commoncrawl_db=$(curl -ks "${commoncrawl_url}" | jq --raw-output .[0]'."cdx-api"' 2>> "${log_execution_file}")
        curl -ks "${commoncrawl_db}?url=*.${domain}/&output=json" | jq -r .url? 2>> "${log_execution_file}" \
            | sed 's/\*\.//g' | sed -e 's_https*://__' -e "s/\/.*//" -e 's/:.*//' -e "/@/d" -e 's/\.$//' \
            | sort -u >> "${tmp_dir}/commoncrawl_domains_output.txt"
        echo "Done!"
        echo "curl -ks \"${commoncrawl_db}?url=*.${domain}/&output=json\" | jq -r .url?" >> "${log_execution_file}"
        sleep 1

        echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing crt.sh... "
        curl -ks "https://crt.sh/?q=%25.${domain}&output=json" | jq -r '.[].name_value' 2>> "${log_execution_file}" | \
            sed 's/\*\.//g' | sort -u >> "${tmp_dir}/crtsh_output.txt"
        echo "SELECT ci.NAME_VALUE NAME_VALUE FROM certificate_identity ci WHERE ci.NAME_TYPE = 'dNSName' AND reverse(lower(ci.NAME_VALUE)) LIKE reverse(lower('%.${domain}'));" \
            | psql -t -h crt.sh -p 5432 certwatch guest \
            | sed -e 's:^ *::g' -e 's:^*\::g' -e '/^$/d' -e 's:*.::g' | sort -u >> "${tmp_dir}/crtsh_output.txt"
        echo "Done!"
        echo "curl -ks \"https://crt.sh/?q=%25.${domain}&output=json\" | jq -r '.[].name_value'" >> "${log_execution_file}"
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

        echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing dns dumpster... "
        dnsdumpster_csrf_token=$(curl "${curl_options[@]}" -L "${dnsdumpster_url}" | grep -i -P  "csrfmiddlewaretoken" | grep -Po '(?<=value=")[^"]*(?=")')
        curl "${curl_options[@]}" -X POST -b "csrftoken=${dnsdumpster_csrf_token}" -H 'Accept: */*' -H 'Content-Type: application/x-www-form-urlencoded' \
            -H "Origin: ${dnsdumpster_url}" -H "Referer: ${dnsdumpster_url}" \
            --data-binary "csrfmiddlewaretoken=${dnsdumpster_csrf_token}&targetip=${domain}&user=free" "${dnsdumpster_url}" \
            | grep -Po '<td class="col-md-4">\K[^<]*' \
            | sort -u \
            | grep "${domain}" >> "${tmp_dir}/dnsdumpster_output.txt"
        echo "Done!"
        echo "curl ${curl_options[@]} -X POST -b \"csrftoken=${dnsdumpster_csrf_token}\" -H 'Accept: */*' -H 'Content-Type: application/x-www-form-urlencoded' \
            -H \"Origin: ${dnsdumpster_url}\" -H \"Referer: ${dnsdumpster_url}\" \
            --data-binary \"csrfmiddlewaretoken=${dnsdumpster_csrf_token}&targetip=${domain}&user=free\" ${dnsdumpster_url}" >> "${log_execution_file}"
        sleep 1

        echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing hackertarget... "
        curl -ks "${hackertarget_url}${domain}" | awk -F',' '{print $1}' | sort -u \
            | grep -v "API count exceeded - Increase Quota with Membership" >> "${tmp_dir}/hackertarget_output.txt"
        echo "Done!"
        echo "curl -ks \"${hackertarget_url}${domain}\"" >> "${log_execution_file}"
        sleep 1

        # netcraft
        # "https://searchdns.netcraft.com/?restriction=site+contains&host=${domain}&position=limited"

        echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing rapiddns... "
        curl -ks "https://rapiddns.io/subdomain/${domain}#result" | grep -Po '<td>\K[^<]*' | grep "${domain}" \
            | sort -u >> "${tmp_dir}/rapiddns_output.txt"
        echo "Done!"
        echo "curl -ks \"https://rapiddns.io/subdomain/${domain}#result\"" >> "${log_execution_file}"
        sleep 1

        if [[ -n "${riskiq_api_key}" ]] && [[ -n "${riskiq_api_secret}" ]]; then
            riskiq_api_check=$(curl "${curl_options[@]}" -w "%{http_code}\n" -u "${riskiq_api_key}:${riskiq_api_secret}" "${riskiq_api_url}?query=${domain}" -o /dev/null)
            if [ "${riskiq_api_check}" -eq 200 ]; then
                echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing riskiq... "
                curl "${curl_options[@]}" -u "${riskiq_api_key}:${riskiq_api_secret}" "${riskiq_api_url}?query=${domain}" \
                     | jq -r .subdomains[]? 2>> "${log_execution_file}" | sort -u | grep -Ev "^.*_domainkey$" >> "${tmp_dir}/riskiq_output.txt"
                sed -i "s/$/\.${domain}/" "${tmp_dir}/riskiq_output.txt"
                echo "Done!"
                echo "curl ${curl_options[@]} -u \"${riskiq_api_key}:${riskiq_api_secret}\" \"${riskiq_api_url}?que\ry=${domain}\" | jq -r .subdomains[]?" >> "${log_execution_file}"
                sleep 1
            fi
        fi

        if [[ -n "${securitytrails_api_key}" ]]; then
            securitytrails_api_check=$(curl "${curl_options[@]}" "${securitytrails_api_url}/ping" -H "APIKEY: ${securitytrails_api_key}" -H 'Accept: application/json' | jq -r '.success' 2>> ${log_execution_file})
            if [ "${securitytrails_api_check}" == "true" ]; then
                echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing security trails... "
                curl "${curl_options[@]}" "${securitytrails_api_url}/domain/${domain}/subdomains?children_only=false&include_inactive=true" \
                    -H "APIKEY: ${securitytrails_api_key}" -H 'Accept: application/json' \
                    | jq -r '.subdomains[]' 2>> "${log_execution_file}" | sort -u >> "${tmp_dir}/securitytrails_output.txt"
                sed -i "s/$/\.${domain}/" "${tmp_dir}/securitytrails_output.txt"
                echo "Done!"
                echo "curl ${curl_options[@]} \"${securitytrails_api_url}/domain/${domain}/subdomains?children_only=false&include_inactive=true\" \
                    -H \"APIKEY: ${securitytrails_api_key}\" -H 'Accept: application/json' \
                    | jq -r '.subdomains[]'" >> "${log_execution_file}"
                sleep 1
            fi
        fi

        if [ "${shodan_use}" == "yes" ]; then
            echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing shodan... "
            shodan search --no-color --fields hostnames hostname:"${domain}" 2>> "${log_execution_file}" | sed -e 's/;/\n/g' -e '/^$/d' | sort -u >> "${tmp_dir}/shodan_subdomain_output.txt"
            echo "Done!"
            echo "shodan search --no-color --fields hostnames hostname:${domain}" >> "${log_execution_file}"
            sleep 1
        fi

        echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing subfinder... "
        subfinder -silent -d "${domain}" >> "${tmp_dir}/subfinder_output.txt" 2>> "${log_execution_file}"
        echo "Done!"
        echo "subfinder -silent -d ${domain}" >> "${log_execution_file}"
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
        echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing threatminer... "
        curl -ks "${threatminer_url}${domain}&rt=5" | jq -r '.results[]?' 2>> "${log_execution_file}" | sort -u >> "${tmp_dir}/threatminer_output.txt"
        echo "Done!"
        echo "curl -ks \"${threatminer_url}${domain}&rt=5\" | jq -r '.results[]?'" >> "${log_execution_file}"
        sleep 1

        if [[ -n "${virustotal_api_url}" ]] && [[ -n "${virustotal_api_key}" ]]; then
            virustotal_api_check=$(curl "${curl_options[@]}" -w "%{http_code}\n" -H "X-Apikey: ${virustotal_api_key}" "${virustotal_api_url}/${domain}/subdomains?limit=40" -o /dev/null)
            if [ "${virustotal_api_check}" -eq 200 ]; then
                echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing virus total... "
                curl "${curl_options[@]}" -H "X-Apikey: ${virustotal_api_key}" "${virustotal_api_url}/${domain}/subdomains?limit=40" \
                    | jq -r '.data[]?.id' 2>> "${log_execution_file}" | sort -u >> "${tmp_dir}/virustotal_output.txt"
                echo "Done!"
                echo "curl ${curl_options[@]} -H \"X-Apikey: ${virustotal_api_key}\" \"${virustotal_api_url}/${domain}/subdomains?limit=40\" \
                    | jq -r '.data[]?.id'" >>  "${log_execution_file}"
                sleep 1
            fi
        fi

        echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing webarchive... "
        curl "${curl_options[@]}" "http://web.archive.org/cdx/search/cdx?url=*.${domain}/*&output=text&fl=original&collapse=urlkey" \
            | sed -e 's_https*://__' -e "s/\/.*//" -e 's/:.*//' -e 's/^www\.//' | sed "/@/d" | sed -e 's/\.$//' | sort -u >> "${tmp_dir}/webarchive_output.txt"
        echo "Done!"
        echo "curl ${curl_options[@]} \"http://web.archive.org/cdx/search/cdx?url=*.${domain}/*&output=text&fl=original&collapse=urlkey\"" >> "${log_execution_file}"
        sleep 1

        if [[ -n "${whoisxmlapi_api_key}" ]] && [[ -n "${whoisxmlapi_subdomain_url}" ]]; then
            echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing whoisxmlapi... "
            curl "${curl_options[@]}" -X POST "${whoisxmlapi_subdomain_url}" -H "Content-Type: application/json" \
                --data '{"apiKey": "'${whoisxmlapi_api_key}'", "domains": {"include": ["'${domain}'"]},"subdomains": {"include": [],"exclude": []}}' \
                | jq -r '.domainsList[]' 2>> "${log_execution_file}" >> "${tmp_dir}/whoisxmlapi_output.txt"
            echo "Done!"
            echo "curl ${curl_options[@]} -X POST \"${whoisxmlapi_subdomain_url}\" -H \"Content-Type: application/json\" \
                --data '{\"apiKey\": \"${whoisxmlapi_api_key}\", \"domains\": {\"include\": [\"${domain}\"]},\"subdomains\": {\"include\": [],\"exclude\": []}}' \
                | jq -r '.domainsList[]'" >> "${log_execution_file}"
        fi
        sleep 1

        if [ "${#dns_wordlists[@]}" -gt 0 ]; then
            echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} We will execute brute force dns with amass, gobuster and dnssearch ${#dns_wordlists[@]} time(s)."
            echo -e "\t Take a break as this step takes a while."
            
            echo "We will execute brute force dns with amass, gobuster and dnssearch ${#dns_wordlists[@]} time(s)." >> "${log_execution_file}"
            for list in "${dns_wordlists[@]}"; do
                index=$(printf "%s\n" "${dns_wordlists[@]}" | grep -En "^${list}$" | awk -F":" '{print $1}')
                if [ -s "${list}" ]; then
                    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Execution number ${index}... "
                    echo "amass enum -src -w ${list} -d ${domain}" >> "${log_execution_file}"
                    echo "gobuster dns -z -q -t ${gobuster_threads} -d ${domain} -w ${list}" >> "${log_execution_file}"
                    echo "dnssearch -consumers 600 -domain ${domain} -wordlist ${list}" >> "${log_execution_file}"
                    amass enum -src -w "${list}" -d "${domain}" >> "${tmp_dir}"/amass_brute_output_"${index}".txt 2>> "${log_execution_file}"
                    gobuster dns -z -q -t "${gobuster_threads}" -d "${domain}" -w "${list}" >> "${tmp_dir}"/gobuster_dns_output_"${index}".txt 2>> "${log_execution_file}"
                    dnssearch -consumers 600 -domain "${domain}" -wordlist "${list}" | \
                    grep "${domain}" >> "${tmp_dir}"/dnssearch_output_"${index}".txt 2>> "${log_execution_file}"
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
        echo "The error occurred in the function domain_recon.sh!" | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
        echo -e "The message was: \n\tMake sure the directories structure was created. Stopping the script!" | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
        echo "The reconnaissance for ${target} failed at $(date +"%Y%m%d %H:%M")" | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
        exit 1
    fi
}

joining_removing_duplicates(){
    if [ -d "${tmp_dir}" ] && [ -d "${report_dir}" ]; then
        echo -en "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Putting all domain search results in one file... "

        if [ -s "${tmp_dir}/alienvault_output.txt" ]; then
            grep -E "^.*\.${domain}" "${tmp_dir}/alienvault_output.txt" >> "${tmp_dir}/domains_found_tmp.txt"
        fi

        if [ -s "${tmp_dir}/amass_output.txt" ]; then
            grep FQDN "${tmp_dir}/amass_output.txt" | awk '{print $1}' | sort -u >> "${tmp_dir}/domains_found_tmp.txt"
        fi

        if [ -s "${tmp_dir}/amass_passive_output.txt" ]; then
            grep FQDN "${tmp_dir}/amass_passive_output.txt" | awk '{print $1}' | sort -u >> "${tmp_dir}/domains_found_tmp.txt"
        fi

        if [ -s "${tmp_dir}/amass_intel.txt" ]; then
            grep -E "^.*\.${domain}" "${tmp_dir}/amass_intel.txt" >> "${tmp_dir}/domains_found_tmp.txt"
        fi
        
        if [ -s "${tmp_dir}/binaryedge_output.txt" ]; then
            grep -E "^.*\.${domain}" "${tmp_dir}/binaryedge_output.txt" >> "${tmp_dir}/domains_found_tmp.txt"
        fi

        if [ -s "${tmp_dir}/censys_output.txt" ]; then
            grep -E "^.*\.${domain}" "${tmp_dir}/censys_output.txt" >> "${tmp_dir}/domains_found_tmp.txt"
        fi

        if [ -s "${tmp_dir}/certspotter_output.txt" ]; then
            grep -E "^.*\.${domain}" "${tmp_dir}/certspotter_output.txt" >> "${tmp_dir}/domains_found_tmp.txt"
        fi

        if [ -s "${tmp_dir}/commoncrawl_domains_output.txt" ]; then
            grep -E "^.*\.${domain}" "${tmp_dir}/commoncrawl_domains_output.txt" >> "${tmp_dir}/domains_found_tmp.txt"
        fi

        if [ -s "${tmp_dir}/crtsh_output.txt" ]; then
            grep -E "^.*\.${domain}" "${tmp_dir}/crtsh_output.txt" >> "${tmp_dir}/domains_found_tmp.txt"
        fi
        
        if [ -s "${tmp_dir}/dnsbufferover_output.txt" ]; then
            grep -E "^.*\.${domain}" "${tmp_dir}/dnsbufferover_output.txt" >> "${tmp_dir}/domains_found_tmp.txt"
        fi

        if [ -s "${tmp_dir}/dnsdb_output.txt" ]; then
            grep -E "^.*\.${domain}" "${tmp_dir}/dnsdb_output.txt" >> "${tmp_dir}/domains_found_tmp.txt"
        fi

        if [ -s "${tmp_dir}/dnsdumpster_output.txt" ]; then
            grep -E "^.*\.${domain}" "${tmp_dir}/dnsdumpster_output.txt" >> "${tmp_dir}/domains_found_tmp.txt"
        fi

        if [ -s "${tmp_dir}/hackertarget_output.txt" ]; then
            grep -E "^.*\.${domain}" "${tmp_dir}/hackertarget_output.txt" >> "${tmp_dir}/domains_found_tmp.txt"
        fi

        if [ -s "${tmp_dir}/rapiddns_output.txt" ]; then
            grep -E "^.*\.${domain}" "${tmp_dir}/rapiddns_output.txt" >> "${tmp_dir}/domains_found_tmp.txt"
        fi

        if [ -s "${tmp_dir}/riskiq_output.txt" ]; then
            grep -E "^.*\.${domain}" "${tmp_dir}/riskiq_output.txt" >> "${tmp_dir}/domains_found_tmp.txt"
        fi

        if [ -s "${tmp_dir}/securitytrails_output.txt" ]; then
            grep -E "^.*\.${domain}" "${tmp_dir}/securitytrails_output.txt" >> "${tmp_dir}/domains_found_tmp.txt"
        fi

        if [ -s "${tmp_dir}/shodan_subdomains_output.txt" ]; then
            grep -E "^.*\.${domain}" "${tmp_dir}/shodan_subdomains_output.txt" >> "${tmp_dir}/domains_found_tmp.txt"
        fi

        if [ -s "${tmp_dir}/subfinder_output.txt" ]; then
            grep -E "^.*\.${domain}" "${tmp_dir}/subfinder_output.txt" >> "${tmp_dir}/domains_found_tmp.txt"
        fi

        if [ -s "${tmp_dir}/threatcrowd_output.txt" ]; then
            grep -E "^.*\.${domain}" "${tmp_dir}/threatcrowd_output.txt" >> "${tmp_dir}/domains_found_tmp.txt"
        fi

        if [ -s "${tmp_dir}/threatminer_output.txt" ]; then
            grep -E "^.*\.${domain}" "${tmp_dir}/threatminer_output.txt" >> "${tmp_dir}/domains_found_tmp.txt"
        fi

        if [ -s "${tmp_dir}/webarchive_output.txt" ]; then
            grep -E "^.*\.${domain}" "${tmp_dir}/webarchive_output.txt" 2> /dev/null >> "${tmp_dir}/domains_found_tmp.txt"
        fi

        if [ -s "${tmp_dir}/whoisxmlapi_output.txt" ]; then
            grep -E "^.*\.${domain}" "${tmp_dir}/whoisxmlapi_output.txt" 2> /dev/null >> "${tmp_dir}/domains_found_tmp.txt"
        fi

        if [ ${#dns_wordlists[@]} -gt 0 ]; then
            files_amass=($(ls -1A "${tmp_dir}/" | grep "amass_brute_output" 2> /dev/null))
            for f in "${files_amass[@]}"; do
                file="${tmp_dir}"/"${f}"
                if [[ -s "${file}" ]]; then
                    grep -Ev "Starting.*names|Querying.*|Average.*performed" "${file}" \
                        | grep "${domain}" | awk '{print $2}' | grep -E "^.*\.${domain}" \
                        | sort -u >> "${tmp_dir}/domains_found_tmp.txt"
                fi
                unset file
            done

            files_gobuster_dns=($(ls -1A "${tmp_dir}/" | grep "gobuster_dns_output" 2> /dev/null))
            for f in "${files_gobuster_dns[@]}"; do
                file="${tmp_dir}"/"${f}"
                if [[ -s "${file}" ]]; then
                    awk '{print $2}' "${file}" | tr '[:upper:]' '[:lower:]' \
                        | grep -E "^.*\.${domain}" | sort -u >> "${tmp_dir}/domains_found_tmp.txt"
                fi
                unset file
            done

            files_dnssearch=($(ls -1A "${tmp_dir}/" | grep "dnssearch_output_" 2> /dev/null))
            for f in "${files_dnssearch[@]}"; do
                file="${tmp_dir}"/"${f}"
                if [[ -s "${file}" ]]; then
                    awk '{print $1}' "${file}" | tr '[:upper:]' '[:lower:]' \
                        | grep -E "^.*\.${domain}" | sort -u >> "${tmp_dir}/domains_found_tmp.txt"
                fi
                unset file
            done
        fi
        echo "Done!"
        
        if [ -s "${tmp_dir}/domains_found_tmp.txt" ]; then
            echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Joining the subdomains and removing duplicates... "
            # Removing duplicated subdomains
            cp "${tmp_dir}/domains_found_tmp.txt" "${tmp_dir}/domains_found_tmp.old"
            sed -E -i 's/^@//g ; s/^\.//g ; s/^-//g ; s/^\://g ; s/\.\./\./g ; s/^http(|s):\/\///g ; s/ //g ; s/^$//g ; /^[[:space:]]*$/d' "${tmp_dir}/domains_found_tmp.txt"
            # Removing duplicated domains per subdomain
            # Example: www.domain.com.domain.com.domain.com
            sed -i "s/\.${domain}//g" "${tmp_dir}/domains_found_tmp.txt"
            sed -i "s/\.$//g" "${tmp_dir}/domains_found_tmp.txt"
            sed -i "s/$/\.${domain}/g" "${tmp_dir}/domains_found_tmp.txt"

            if tr '[:upper:]' '[:lower:]' < "${tmp_dir}/domains_found_tmp.txt" | sort -u > "${report_dir}/domains_found.txt" ; then
                sed -i '/owasp.*nonce/d ; /_/d ; /\*/d ; /^[[:blank:]]/d ; /</d ; />/d' "${report_dir}/domains_found.txt"
                echo "Done!"
            fi

            if [ ${#excluded[@]} -gt 0 ] && [ -s "${report_dir}/domains_found.txt" ]; then
                echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Excluding the subdomains from command line option... "
                for subdomain in "${excluded[@]}"; do
                    sed -i "/^${subdomain}$/d" "${report_dir}/domains_found.txt"
                done
                unset subdomain
                # Fixing blank lines after excluding domains
                sed -i '/^$/d' "${report_dir}/domains_found.txt"
                echo "Done!"
            fi

            if [ -s "${exclude_domains_list}" ] && [ -s "${report_dir}/domains_found.txt" ]; then
                echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Excluding the subdomains from file list option... "
                cp "${exclude_domains_list}" "${report_dir}/domains_excluded.txt"
                while read -r excluded_domain; do
                    sed -i "s/${excluded_domain}//" "${report_dir}/domains_found.txt"
                done < "${exclude_domains_list}"
                # Fixing blank lines after excluding domains
                sed -i '/^$/d' "${report_dir}/domains_found.txt"
                echo "Done!"
            fi
        fi

        echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Looking for Zone Transfer... "
        if [ -s "${tmp_dir}/zone_transfer.txt" ]; then
            cp "${tmp_dir}/zone_transfer.txt" "${report_dir}/zone_transfer.txt"
            echo "Done!"
        else
            echo "Fail!"
            echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Does not possible perfom zone transfer!"
        fi

    else
        echo "Fail!"
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Make sure the directories structure was created. Stopping the script."
        echo "The error occurred in the function domain_recon.sh!" | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
        echo -e "The message was: \n\tMake sure the directories structure was created. Stopping the script." | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
        echo "The reconnaissance for ${domain} failed at $(date +"%Y%m%d %H:%M")" | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
        exit 1
    fi
}

managing_the_files(){
    subdomains_file="$1"
    if [ -s "${subdomains_file}" ]; then
        echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Getting the IPs and aliases of the domain and subdomains... "
        # Domains and subdomains resolution
        "massdns" -q -r "${massdns_resolvers_file}" -t A -o S \
            -w "${tmp_dir}/domains_massdns_resolution.txt" "${subdomains_file}" > /dev/null 2>&1

        for d in $(cat "${subdomains_file}"); do
            dig +nocmd +nocomments +noquestion +noqr +nostats +timeout=2 -t A "${d}" >> "${tmp_dir}/domains_dig_command_resolution.txt"
        done

        for d in $(cat "${subdomains_file}"); do
            host -W 2 -t A "${d}" >> "${tmp_dir}/domains_host_command_resolution.txt"
        done

        # Organizing and handling domain files
        for file_resolution in "${tmp_dir}/domains_massdns_resolution.txt" "${tmp_dir}/domains_dig_command_resolution.txt" "${tmp_dir}/domains_host_command_resolution.txt"; do
            cp "${file_resolution}" "${file_resolution}.old"
            if [[ -s "${file_resolution}" ]];  then
                sed -i "s/${domain}\./${domain}/g" "${file_resolution}"
                sed -i "s/\.$//g" "${file_resolution}"
                sed -i 's/\.[[:blank:]]/ /g' "${file_resolution}"
                sed -i "s/^@//g" "${file_resolution}"
                sed -i "s/^\.//g" "${file_resolution}"
 
                # Domains with IPs
                grep -E "${IPv4_regex}$" "${file_resolution}" \
                    | grep "${domain}" | sort -u | awk '{print $1"\t"$NF}' >> "${report_dir}/domains_external_ipv4.txt"
                #grep -E "${IPv6_regex}$" "${tmp_dir}/domains_massdns_resolution_ipv6.txt" \
                #    | grep "${domain}" | sort -u | awk '{print $1"\t"$3}' >> "${report_dir}/domains_external_ipv6.txt"

                # Domains aliases
                grep -E "CNAME|is.an.alias" "${file_resolution}" | grep "${domain}" | sort -u | awk '{print $1"\t"$NF}' >> "${report_dir}/domains_aliases.txt"
            fi
        done
        echo "Done!"

        # Removing private IPs
        echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Separating internal and external IPs... "
        if [ -s "${report_dir}/domains_external_ipv4.txt" ]; then
            grep -E '(^\S+\s+\b10\.\b([01]?[0-9][0-9]?|2[0-4][0-9]|25[0-5])\..*|^\S+\s+(127\..*)\b|^\S+\s+172\.1[6789]\..*|^\S+\s+172\.2[0-9]\..*|^\S+\s+172\.3[01]\..*|^\S+\s+192\.168\..*)'$ "${report_dir}/domains_external_ipv4.txt" >> "${report_dir}/domains_internal_ipv4.txt"
            sed -i -E '/\b10\.\b([01]?[0-9][0-9]?|2[0-4][0-9]|25[0-5])\..*$/d ; /^\S+\s+(127\..*)\b$/d; /172\.1[6789]\..*$/d ; /172\.2[0-9]\..*$/d ; /172\.3[01]\..*$/d ; /192\.168\..*$/d' "${report_dir}/domains_external_ipv4.txt"
            cat "${report_dir}/domains_external_ipv4.txt" | awk '{print $1}' | sort -u >> "${tmp_dir}/domains_alive_tmp.txt"
        fi
        echo "Done!"

        # Getting sudomain aliases
        echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Separating subdomain aliases... "
        if [ -s "${report_dir}/domains_aliases.txt" ]; then
            cat "${report_dir}/domains_aliases.txt" | awk '{print $1}' | sort -u >> "${tmp_dir}/domains_alive_tmp.txt"
        fi
        echo "Done!"

        if sort -u -o "${report_dir}/domains_alive.txt" "${tmp_dir}/domains_alive_tmp.txt"; then
            # Unavailable domains
            echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Separating live subdomains from unresponsive subdomains... "
            cp "${subdomains_file}" "${report_dir}/domains_without_resolution.txt"
            for d in $(cat "${report_dir}/domains_alive.txt"); do
                sed -i "/${d}/d" "${report_dir}/domains_without_resolution.txt"
            done
            echo "Done!"

            # Sorting out...
            echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Removing duplicate subdomains... "
            sort -u -o "${report_dir}/domains_aliases.txt" "${report_dir}/domains_aliases.txt" 2> /dev/null
            sort -u -o "${report_dir}/domains_alive.txt" "${report_dir}/domains_alive.txt" 2> /dev/null
            sort -u -o "${report_dir}/domains_internal_ipv4.txt" "${tmp_dir}/domains_found_tmp_internal_ips.txt" 2> /dev/null
            sort -u -o "${report_dir}/domains_external_ipv4.txt" "${report_dir}/domains_external_ipv4.txt" 2> /dev/null
            #sort -u -o "${report_dir}/domains_external_ipv6.txt" "${report_dir}/domains_external_ipv6.txt" 2> /dev/null
            sort -u -o "${report_dir}/domains_without_resolution.txt" "${report_dir}/domains_without_resolution.txt" 2> /dev/null
            echo "Done!"
        else
            echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Error organizing and handling subdomain files!"
            echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Could not find any live domains, exiting!"
            echo "The error occurred in the function diff_domains.sh!" | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
            echo -e "The message was: \n\tError organizing and handling subdomain files!\n\tCould not find any live domains, exiting!" | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
            echo "The reconnaissance for ${domain} failed at $(date +"%Y%m%d %H:%M")" | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
            exit 1
        fi

    else
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} The file with all domains from initial recon does not exist or is empty."
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Look all files from initial recon in ${tmp_dir} and fix the problem!"
        echo "The error occurred in the function diff_domains.sh!" | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
        echo -e "The message was: \n\tThe file with all domains from initial recon does not exist or is empty.\n\tLook all files from initial recon in ${tmp_dir} and fix the problem!" | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
        echo "The reconnaissance for ${domain} failed at $(date +"%Y%m%d %H:%M")" | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
        exit 1
    fi    
}
