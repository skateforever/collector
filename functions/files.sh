#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * joining_subdomains                                    #
#   * organizing_subdomains                                 #
#                                                           #
#############################################################            

joining_subdomains(){
    echo -en "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Putting all domain search results in one file... " \
        | tee -a "${log_execution_file}"
    if [ -d "${tmp_dir}" ] && [ -d "${report_dir}" ]; then
        if [ -s "${tmp_dir}/alienvault_output.json" ]; then
            cat "${tmp_dir}/alienvault_output.json" \
                | jq --raw-output '.passive_dns[]?.hostname' \
                | sort -u >> "${tmp_dir}/alienvault_output.txt"
        fi

        if [ -s "${tmp_dir}/amass_active_output.txt" ]; then
            grep FQDN "${tmp_dir}/amass_active_output.txt" \
                | awk '{print $1, ORS="\n"; $6}'\
                | grep "${domain}" \
                | sort -u >> "${tmp_dir}/domains_found.tmp"
        fi

        if [ -s "${tmp_dir}/amass_passive_output.txt" ]; then
            grep FQDN "${tmp_dir}/amass_passive_output.txt" \
                | awk '{print $1, ORS="\n"; $6}'\
                | grep "${domain}" \
                | sort -u >> "${tmp_dir}/domains_found.tmp"
        fi

        if [ -s "${tmp_dir}/builtwith_subdomain_output.json" ]; then
            cat "${tmp_dir}/builtwith_subdomain_output.json" \
                | jq -r '.Results[].Result.Paths[].SubDomain' \
                | sort -u | sed "s/$/\.${domain}/g" >> "${tmp_dir}/domains_found.tmp"
        fi

        if [ -s "${tmp_dir}/certspotter_output.json" ]; then
            cat "${tmp_dir}/certspotter_output.json" \
                | jq -r '.[].dns_names[]' 2>> ${log_execution_file} \
                | sed 's/\"//g' | sed 's/\*\.//g' \
                | sort -u | grep "${domain}" >> "${tmp_dir}/domains_found.tmp"
        fi

        if [ -s "${tmp_dir}/commoncrawl_output.json" ]; then
            cat "${tmp_dir}/commoncrawl_output.json" \
                | jq -r '.url?' \
                | sed 's/\*\.//g' | sed -e 's_https*://__' -e "s/\/.*//" -e 's/:.*//' -e "/@/d" -e 's/\.$//' \
                | sort -u >> "${tmp_dir}/domains_found.tmp"
        fi

        if [ -s "${tmp_dir}/crtsh_output.json" ]; then
            cat "${tmp_dir}/crtsh_output.json" \
                | jq -r '.[].name_value' \
                | sed 's/\*\.//g' \
                | sort -u >> "${tmp_dir}/domains_found.tmp"
        fi
        
        if [ -s "${tmp_dir}/dnsdumpster_output.json" ]; then
            cat "${tmp_dir}/dnsdumpster_out.json" \
                | jq -r '.a[].host' \
                | sort -u >> "${tmp_dir}/domains_found.tmp"
        fi

        if [ -s "${tmp_dir}/hackertarget_output.txt" ]; then
            awk -F',' '{print $1}' "${tmp_dir}/hackertarget_output.txt" \
                | sort -u >> "${tmp_dir}/domains_found.tmp"
        fi

        if [ -s "${tmp_dir}/rapiddns_output.txt" ]; then
            grep -Po '<td>\K[^<]*' "${tmp_dir}/rapiddns_output.txt" \
                | grep -E "^.*\.${domain}" "${tmp_dir}/rapiddns_output.txt" \
                >> "${tmp_dir}/domains_found.tmp"
        fi

        if [ -s "${tmp_dir}/securitytrails_output.json" ]; then
            cat "${tmp_dir}/securitytrails_output.json" \
                | jq -r '.subdomains[]' \
                | sed "s/$/i\.${domain}/" \
                sort -u >> "${tmp_dir}/domains_found.tmp"
        fi

        if [ -s "${tmp_dir}/shodan_output.txt" ]; then
            sed -i -e 's/;/\n/g' -e '/^$/d' "${tmp_dir}/shodan_output.txt"
            sort -u "${tmp_dir}/shodan_output.txt" \
                | grep -E "^.*\.${domain}" >> "${tmp_dir}/domains_found.tmp"
        fi

        if [ -s "${tmp_dir}/subfinder_output.txt" ]; then
            grep -E "^.*\.${domain}" "${tmp_dir}/subfinder_output.txt" >> "${tmp_dir}/domains_found.tmp"
        fi

        if [ -s "${tmp_dir}/tlsx_output.json" ]; then
            cat "${tmp_dir}/tlsx_output.json" | jq -r '.subject_an[]' grep -E "^.*\.${domain}" >> "${tmp_dir}/domains_found.tmp"
        fi

        if [ -s "${tmp_dir}/virustotal_output.json" ]; then
            cat "${tmp_dir}/virustotal_output.json" \
                | jq -r '.data[]?.id' \
                | sort -u >> "${tmp_dir}/domains_found.tmp"
        fi

        if [ -s "${tmp_dir}/webarchive_output.txt" ]; then
            cat "${tmp_dir}/webarchive_output.txt" \
                | sed -e 's_https*://__' -e "s/\/.*//" -e 's/:.*//' -e 's/^www\.//' \
                | sed "/@/d" | sed -e 's/\.$//' | sort -u >> "${tmp_dir}/domains_found.tmp"
        fi

        if [ -s "${tmp_dir}/whoisxmlapi_output.json" ]; then
            cat "${tmp_dir}/whoisxmlapi_output.json" \
                | jq -r '.domainsList[]' \
                | sort -u \
                | grep -E "^.*\.${domain}" 2> /dev/null >> "${tmp_dir}/domains_found.tmp"
        fi

        if [ ${#dns_wordlists[@]} -gt 0 ]; then
            files_amass=($(ls -1A "${tmp_dir}/" | grep "amass_brute_output" 2> /dev/null))
            for f in "${files_amass[@]}"; do
                file="${tmp_dir}"/"${f}"
                if [[ -s "${file}" ]]; then
                    grep -Ev "Starting.*names|Querying.*|Average.*performed" "${file}" \
                        | grep "${domain}" | awk '{print $2}' | grep -E "^.*\.${domain}" \
                        | sort -u >> "${tmp_dir}/domains_found.tmp"
                fi
                unset file
            done

            files_gobuster_dns=($(ls -1A "${tmp_dir}/" | grep "gobuster_dns_output" 2> /dev/null))
            for f in "${files_gobuster_dns[@]}"; do
                file="${tmp_dir}"/"${f}"
                if [[ -s "${file}" ]]; then
                    awk '{print $2}' "${file}" | tr '[:upper:]' '[:lower:]' \
                        | grep -E "^.*\.${domain}" | sort -u >> "${tmp_dir}/domains_found.tmp"
                fi
                unset file
            done

            files_dnssearch=($(ls -1A "${tmp_dir}/" | grep "dnssearch_output_" 2> /dev/null))
            for f in "${files_dnssearch[@]}"; do
                file="${tmp_dir}"/"${f}"
                if [[ -s "${file}" ]]; then
                    awk '{print $1}' "${file}" | tr '[:upper:]' '[:lower:]' \
                        | grep -E "^.*\.${domain}" | sort -u >> "${tmp_dir}/domains_found.tmp"
                fi
                unset file
            done
        fi

        #if [ -s  "${tmp_dir}/zone_transfer.txt" ]; then
        #    
        #fi
        
        if [ -s "${tmp_dir}/domains_found.tmp" ]; then
            echo "Done!"
            echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Joining the subdomains and removing duplicates... "
            # Removing duplicated subdomains
            cp "${tmp_dir}/domains_found.tmp" "${tmp_dir}/domains_found_tmp.old"
            sed -E -i 's/^@//g ; s/^\.//g ; s/^-//g ; s/^\://g ; s/\.\./\./g ; s/^http(|s):\/\///g ; s/ //g ; s/^$//g ; /^[[:space:]]*$/d' "${tmp_dir}/domains_found.tmp"
            # Removing duplicated domains per subdomain
            # Example: www.domain.com.domain.com.domain.com
            sed -i "s/\.${domain}//g" "${tmp_dir}/domains_found.tmp"
            sed -i "s/\.$//g" "${tmp_dir}/domains_found.tmp"
            sed -i "s/$/\.${domain}/g" "${tmp_dir}/domains_found.tmp"

            if tr '[:upper:]' '[:lower:]' < "${tmp_dir}/domains_found.tmp" | sort -u > "${report_dir}/domains_found.txt" ; then
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
        else
            echo "Fail!"
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

organizing_subdomains(){
    subdomains_file="$1"
    if [ -s "${subdomains_file}" ]; then
        echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Getting the IPs and aliases of the domain and subdomains... "
        # Domains and subdomains resolution
        if [ -s "${massdns_resolvers_file}" ]; then
            "massdns" -q -r "${massdns_resolvers_file}" -t A -o S \
                -w "${tmp_dir}/domains_massdns_resolution.txt" "${subdomains_file}" > /dev/null 2>&1
        fi

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

        echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Separating live subdomains from unresponsive subdomains... "
        if sort -u -o "${report_dir}/domains_alive.txt" "${tmp_dir}/domains_alive_tmp.txt"; then
            # Unavailable domains
            cp "${subdomains_file}" "${report_dir}/domains_without_resolution.txt"
            for d in $(cat "${report_dir}/domains_alive.txt"); do
                sed -i "/${d}/d" "${report_dir}/domains_without_resolution.txt"
            done
            echo "Done!"

        else
            echo "Fail!"
            echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Error organizing and handling subdomain files!"
            echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Could not find any live domains, exiting!"
            echo "The error occurred in the function diff_domains.sh!" | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
            echo -e "The message was: \n\tError organizing and handling subdomain files!\n\tCould not find any live domains, exiting!" | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
            echo "The reconnaissance for ${domain} failed at $(date +"%Y%m%d %H:%M")" | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
            exit 1
        fi
 
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
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} The file with all domains from initial recon does not exist or is empty."
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Look all files from initial recon in ${tmp_dir} and fix the problem!"
        echo "The error occurred in the function diff_domains.sh!" | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
        echo -e "The message was: \n\tThe file with all domains from initial recon does not exist or is empty.\n\tLook all files from initial recon in ${tmp_dir} and fix the problem!" | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
        echo "The reconnaissance for ${domain} failed at $(date +"%Y%m%d %H:%M")" | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
        exit 1
    fi    
}
