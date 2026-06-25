#!/bin/bash
#############################################################
# Getting information about infrastructure (IPs, ASN, CIDR) #
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * infra_data                                            #
#   * nmap_scan                                             #
#   * shodan_scan                                           #
#                                                           #
#############################################################

infra_data(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Getting information about infrastructure... "
    if [ -s "${report_dir}/domains_external_ipv4.txt" ]; then
        echo -e "\n${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Getting AS information... "
        # To avoid the warning message: "Warning: RIPE flags used with a traditional server."
        # The -- option is needed.
        echo "AS      | IP               | BGP Prefix          | CC | Registry | Allocated  | AS Name" >> "${report_dir}/infra_as.txt"
        while IFS= read -r IP; do
            echo -e "\n" >> "${log_execution_file}"
            echo "whois -h whois.cymru.com -- \"-v ${IP}\" | tail -n +2 >> \"${report_dir}/infra_as.txt\"" >> "${log_execution_file}"
            whois -h whois.cymru.com -- "-v ${IP}" | tail -n +2 >> "${report_dir}/infra_as.txt"
        done < <(awk '{print $2}' "${report_dir}/domains_external_ipv4.txt" | sort -u)
        echo "Done!"

        echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Getting target IPv4... "
        if [ -s "${report_dir}/domains_external_ipv4.txt" ] ; then
            awk '{print $2}' "${report_dir}/domains_external_ipv4.txt" | sort -u >> "${tmp_dir}/infra_ipv4.tmp"
            if [[ -s "${tmp_dir}/infra_ipv4.tmp" ]]; then
                sort -u -o "${report_dir}/infra_ipv4.txt" "${tmp_dir}/infra_ipv4.tmp"
            	echo "Done!"
            fi
        else
            echo "Fail!"
        fi

        echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Getting target IPv6... "
        if [ -s "${report_dir}/domains_external_ipv6.txt" ] ; then
            awk '{print $2}' "${report_dir}/domains_external_ipv6.txt" | sort -u >> "${tmp_dir}/infra_ipv6.tmp"
            if [[ -s "${tmp_dir}/infra_ipv6.tmp" ]]; then
                sort -u -o "${report_dir}/infra_ipv6.txt" "${tmp_dir}/infra_ipv6.tmp"
            	echo "Done!"
            fi
        else
            echo "Fail!"
        fi
        
        echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Getting target blocks... "
        if [ -s "${report_dir}/infra_as.txt" ]; then
            ownerid=$(whois "${domain}" 2> /dev/null | grep -E "^ownerid:" | awk '{print $2}')
            for IP in $(grep -Ev "Google|Microsoft|Azure|AWS|Amazon|Cloudflare" "${report_dir}/infra_as.txt" | tail -n+2 | awk '{print $3}'); do
                if [[ -n "${ownerid}" ]]; then
                    if whois "${IP}" 2> /dev/null | grep -q "${ownerid}"; then
                        sleep 3
                        # IPv4 block
                        whois "${IP}" | grep -E "${IP%%.*}.*\/[0-9]{2}$" >> "${tmp_dir}/infra_blocks.tmp"
                        # IPv6 block
                        # ?
                    fi
                fi
            done
        fi
        unset ownerid

        [[ -s "${tmp_dir}/infra_blocks.tmp" ]] && \
            sort -u -o "${report_dir}/infra_blocks.txt" "${tmp_dir}/infra_blocks.tmp"
        echo "Done!"
    else
        echo "Fail!"
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} File ${yellow}${report_dir}/domains_external_ipv4.txt${reset} ${red}does not exist${reset} or ${red}is empty!${reset}"
        echo -e "File ${report_dir}/domains_external_ipv4.txt does not exist or is empty!" | notify -nc -silent -id "${notify_recon_channel}" > /dev/null 2>&1
        message "${domain}" failed
    fi
}

nmap_scan(){
        if [ -s "${report_dir}/infra_ipv4.txt" ]; then
            echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Getting information about IPs with nmap... "
            echo -e "\nnmap ${nmap_options[@]} -iL \"${report_dir}/infra_ipv4.txt\" > \"${nmap_dir}/nmap_scan.txt\"" >> "${log_execution_file}"
            nmap "${nmap_options[@]}" -iL "${report_dir}/infra_ipv4.txt" > "${nmap_dir}/nmap_scan.txt"
            echo "Done!"
        fi
}

shodan_scan(){
    if [ "${shodan_use}" == "yes" ] && [ -s "${report_dir}/infra_blocks.txt" ]; then
        echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing shodan scan on target's IPs... "
        shodan_scans=$(shodan info | grep "Scan.*:" | awk '{print $4}')
        if [ "${shodan_scan_main_domain}" == "yes" ] && [ "${shodan_scans}" -gt 1 ]; then
            for IP in $(cat "${report_dir}/infra_ipv4.txt"); do
                echo "shodan scan submit ${IP} > ${shodan_dir}/shodan_scan.txt" >> "${log_execution_file}"
                "shodan" scan submit "${IP}" > "${shodan_dir}/shodan_scan.txt" 2>> "${log_execution_file}" &
            done
        fi
        echo "Done!"
    fi
}
