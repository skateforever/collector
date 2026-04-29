#!/bin/bash
#############################################################
# Getting information about infrastructure (IPs, ASN, CIDR) #
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * infra_data                                            #
#   * nmap_scan                                             #
#   * shodan_recon                                          #
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
            nmap -n -PN -sT -iL "${report_dir}/infra_ipv4.txt" \
                --exclude 10.0.0.0/8,172.16.0.0/12,192.168.0.0/16 \
                --max-retries 3 --host-timeout 3 > "${report_dir}/nmap_scan.txt"
            echo "Done!"
        fi
}

shodan_recon(){
    if [ "${shodan_use}" == "yes" ] && [ -s "${report_dir}/infra_blocks.txt" ]; then
        echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing shodan network scan... " 
        for block in $(cat "${report_dir}/infra_blocks.txt" | awk '{print $1}'); do
            unset user_agent
            user_agent="$(get_user_agent)"
            network=$(echo ${block} | awk -F'/' '{print $1}')
            cidr=$(echo ${block} | awk -F'/' '{print $2}')
            rm_network=$(echo ${network} | awk -F'.' '{print $1"."$2"."$3"."}')
            ip_range=$(curl "${curl_options[@]}" -H "User-agent: ${user_agent}" -s "http://jodies.de/ipcalc" -d "host=${network}&mask1=${cidr}" 2> /dev/null | sed 's/<font color="#000000">/\\\n/g ; s/\\//g' | grep -E "HostMin:|HostMax:" | awk '{print $3}' | sed 's/.*>//' | tr '\n' ' ' | sed "s/${rm_network}//g ; s/.$//")
            total_ip=$(curl "${curl_options[@]}" -H "User-agent: ${user_agent}" -s "http://jodies.de/ipcalc" -d "host=${network}&mask1=${cidr}" 2> /dev/null | sed 's/<font color="#000000">/\\\n/g ; s/\\//g' | grep -E "Hosts/Net:" | awk '{print $3}' | sed 's/.*>//' | tr '\n' ' ')
            shodan_recons=$(shodan info 2> /dev/null | grep "Scan.*:" | awk '{print $4}')
            shodan_count=0
            if [ "${shodan_recons}" -gt "${total_ip}" ]; then
                for ip in $(seq ${ip_range}); do
                    [[ "${shodan_count}" -eq "${shodan_recon_total}" ]] && break
                    "shodan" scan submit "${rm_network}${ip}" > "${shodan_dir}/shodan_${rm_network}${ip}" 2> "${log_execution_file}" &
                    (( shodan_count+=1 ))
                done
            fi
        done
        echo "Done!"

        shodan_recons=$(shodan info | grep "Scan.*:" | awk '{print $4}')
        if [ "${shodan_recon_main_domain}" == "yes" ] && [ "${shodan_recons}" -gt 1 ]; then
            echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing shodan domain scan... " 
            main_domain_ip=$(timeout 5s host -W 3 -t A ${domain} 2> /dev/null | awk '{print $4}' | head -n1)
            [[ -n "${main_domain_ip}" ]] && \
                "shodan" scan submit "${main_domain_ip}" > "${shodan_dir}/shodan_${domain}" 2> "${log_execution_file}" &
            echo "Done!"
        fi
    fi
        
}

vhost_check(){
    echo -n "Looking for vhost with dead subdomains... "

    curl_base








    if [[ -s "${report_dir}/domains_external_ipv4.txt" && -s "${report_dir}/domains_without_resolution.txt" ]]; then
        for subdomain in $(cat "${report_dir}/domains_without_resolution.txt"); do
            for IP in $(awk '{print $2}' "${report_dir}/domains_external_ipv4.txt" | sort -u); do
                curl "${curl_options[@]}" --resolve "${subdomain}":80:"${IP}" http://"${subdomain}"
                curl "${curl_options[@]}" --resolve "${subdomain}":443:"${IP}" https://"${subdomain}"
            done
        done
        gobuster vhost -u https://example.com -w /path/to/wordlist.txt
        webfinder -t https://x.com/ -ip tst.txt -o x.txt --random-agent
    fi
    

# Basic vhost discovery with a wordlist
ffuf -w subdomains.txt -u https://TARGET -H "Host: FUZZ.TARGET" -mc all

# With common response code filtering
ffuf -w subdomains.txt -u https://TARGET -H "Host: FUZZ.TARGET" -mc 200,204,301,302,307,401,403,405

# Using IP address instead of domain (bypasses some load balancers)
ffuf -w subdomains.txt -u http://TARGET_IP -H "Host: FUZZ.TARGET" -mc all

# With auto-calibration to filter out false positives
ffuf -w subdomains.txt -u https://TARGET -H "Host: FUZZ.TARGET" -ac -mc all

# Multiple host header techniques
ffuf -w subdomains.txt -u https://TARGET -H "Host: FUZZ.TARGET" -H "X-Forwarded-Host: FUZZ.TARGET" -mc all

# With size and word count filtering to find subtle differences
ffuf -w subdomains.txt -u https://TARGET -H "Host: FUZZ.TARGET" -mc all -fs 0 -fw 0

ffuf -w subdomains.txt -u https://target.com \
    -H "Host: FUZZ.target.com" \
    -ac \
    -mc 200,204,301,302,307,401,403,405,500 \
    -o vhost_results.txt \
    -of json \
    -v


        vhost_original="$(timeout --signal=9 1 curl -siLk -o /dev/null -w "%{response_code}","%{size_download}" "$IP" --no-keepalive)"


#    if [[ -s "${report_dir}/domains_without_resolution.txt" ]] && [[ -s "${report_dir}/domains_external_ipv4.txt" ]]; then
#        # Getting the IPs
#        for IP in $(awk '{print $2}' "${report_dir}/domains_external_ipv4.txt" | sort -u) ; do
#            #Getting the ports
#            for PORT in ${web_port_detect[@]}; do
#                # Getting the dead subdomains
}
