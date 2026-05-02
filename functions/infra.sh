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
        echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Getting AS information... "
        # To avoid the warning message: "Warning: RIPE flags used with a traditional server."
        # The -- option is needed.
        echo "AS      | IP               | BGP Prefix          | CC | Registry | Allocated  | AS Name" >> "${report_dir}/infra_as.txt"
        while IFS= read -r IP; do
            echo "whois -h whois.cymru.com -- \"-v ${IP}\" | tail -n +2 >> \"${report_dir}/infra_as.txt\"" >> "${log_execution_file}"
            whois -h whois.cymru.com -- "-v ${IP}" | tail -n +2 >> "${report_dir}/infra_as.txt"
        done < <(awk '{print $2}' "${report_dir}/domains_external_ipv4.txt" | sort -u)
        echo "Done!"

        echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Getting target IPs... "
        if [ -s "${report_dir}/domains_external_ipv4.txt" ] ; then
            awk '{print $2}' "${report_dir}/domains_external_ipv4.txt" | sort -u >> "${tmp_dir}/infra_ipv4.tmp"
            if [[ -s "${tmp_dir}/infra_ipv4.tmp" ]]; then
                sort -u -o "${report_dir}/infra_ipv4.txt" "${tmp_dir}/infra_ipv4.tmp"
            fi
            awk '{print $2}' "${report_dir}/domains_external_ipv6.txt" | sort -u >> "${tmp_dir}/infra_ipv6.tmp"
            if [[ -s "${tmp_dir}/infra_ipv6.tmp" ]]; then
                sort -u -o "${report_dir}/infra_ipv6.txt" "${tmp_dir}/infra_ipv6.tmp"
            fi
            echo "Done!"
        else
            echo "Fail!"
        fi
        
        echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Getting target blocks... "
        if [ -s "${report_dir}/infra_as.txt" ]; then
            for IP in $(grep -Ev "Google|Microsoft|Azure|AWS|Amazon|Cloudflare" "${report_dir}/infra_as.txt" | tail -n+2 | awk '{print $3}'); do
                ownerid=$(whois "${domain}" 2> /dev/null | grep -E "^ownerid:" | awk '{print $2}')
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
    fi
}

nmap_scan(){
        if [ -s "${report_dir}/infra_ipv4.txt" ]; then
            echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Getting information about IPs with nmap... "
            echo "nmap -n -PN -sT -iL \"${report_dir}/infra_ipv4.txt\" \
                --exclude 10.0.0.0/8,172.16.0.0/12,192.168.0.0/16 \
                --max-retries 3 --host-timeout 3 > \"${report_dir}/nmap_scan.txt\"" >> "${log_execution_file}"
            nmap -n -PN -sT -iL "${report_dir}/infra_ipv4.txt" \
                --exclude 10.0.0.0/8,172.16.0.0/12,192.168.0.0/16 \
                --max-retries 3 --host-timeout 3 > "${report_dir}/nmap_scan.txt"
            echo "Done!"
        fi
}

shodan_scan(){
    if [ "${shodan_use}" == "yes" ] && [ -s "${report_dir}/infra_blocks.txt" ]; then
        echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing shodan scan on target's IPs... "
        shodan_scans=$(shodan info | grep "Scan.*:" | awk '{print $4}')
        if [ "${shodan_scan_main_domain}" == "yes" ] && [ "${shodan_scans}" -gt 1 ]; then
            for IP in "$(cat ${report_dir}/infra_ipv4.txt)"; do
                echo "shodan scan submit ${IP} > ${shodan_dir}/shodan_scan.txt" >> "${log_execution_file}"
                "shodan" scan submit "${IP}" > "${shodan_dir}/shodan_scan.txt" 2>> "${log_execution_file}" &
            done
        fi
        echo "Done!"
    fi
}

vhost_check(){
    echo -n "Looking for vhost with dead subdomains... "

    target="$1"
    vhost_principal_name="$2"
    vhost_name_file="$3"
    vhost_ip_file="$4"

    if [[ -s "${report_dir}/domains_external_ipv4.txt" && -s "${report_dir}/domains_without_resolution.txt" ]]; then
        for subdomain in "$(cat ${vhost_principal_name})"; do
            vhost_original="$(timeout --signal=9 1 curl -siLk -o /dev/null -w "%{response_code}","%{size_download}" "$IP" --no-keepalive)"
            subdomain_validation=$(curl -s -k -A "$ua" "${subdomain}")
            subdomain_size=$(echo "${subdomain_validation}" | wc -c)
            subdomain_hash=$(echo "${subdomain_validation}" | md5sum | awk '{print $1}')
            
            for vhost in "$(cat ${vhost_name_file})"; do
                for IP in "$(cat ${vhost_name_file})"; do
                    for port in "${PORTS[@]}"; do
                        user_agent=$(get_user_agent)
                        vhost_validation=$(curl -s -k -A "$ua" -H "Host: $vhost" http://$ip:$port)
                        vhost_size=$(echo "${vhost_validation}" | wc -c)
                        vhost_hash=$(echo "${vhost_validation}" | md5sum | awk '{print $1}')
                        
                        key="${ip}:${port}"
                        base_size=${BASE_SIZE[$key]}
                        base_hash=${BASE_HASH[$key]}
                        
                        if [[ "${subdomain_size}" != "${vhost_size}" ]] || [[ "${subdomain_hash}" != "${vhost_hash}" ]]; then
                            echo -e "${vhost}\t${IP}:${port}"
                        fi
                        ffuf -w subdomains.txt -u https://TARGET -H "Host: FUZZ.TARGET" -mc all
                        gobuster vhost -u https://example.com -w /path/to/wordlist.txt
                    done
                done
            done
        done
    else
        echo "Fail!"
    fi
}
