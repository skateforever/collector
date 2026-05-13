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
#   * vhost_check                                           #
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
            echo -e "\nnmap ${nmap_options[@]} -iL \"${report_dir}/infra_ipv4.txt\" > \"${report_dir}/nmap_scan.txt\"" >> "${log_execution_file}"
            nmap "${nmap_options[@]}" -iL "${report_dir}/infra_ipv4.txt" > "${report_dir}/nmap_scan.txt"
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
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Looking for vhost with dead subdomains... "
    echo -e "\n" >> "${log_execution_file}"

    vhost_name_file="$1"
    vhost_ip_file="$2"

    if [[ -s "${vhost_ip_file}" && -s "${report_dir}/infra_ipv4.txt" ]]; then
        for IP in "$(cat ${vhost_ip_file})"; do
            for port in "${webapp_port_detect[@]}"; do
                user_agent=$(get_user_agent)
                unresponsive_vhost="$(tr -dc 'a-z' </dev/urandom | fold -w 10 | head -n1).${domain}"
                # curl
                echo "curl ${curl_options[@]} -L -H \"User-Agent: ${user_agent}\" -H \"Host: ${unresponsive_vhost}\" \"http://${IP}:${port}\"" >> "${log_execution_file}"
                curl_unresponsive_content=$(curl "${curl_options[@]}" -L -H "User-Agent: ${user_agent}" -H "Host: ${unresponsive_vhost}" http://${IP}:${port} 2>> "${log_execution_file}")
                curl_unresponsive_size=$(echo "${curl_unresponsive_content}" | wc -c)
                curl_unresponsive_hash=$(echo "${curl_unresponsive_content}" | md5sum | awk '{print $1}')
                # httpx
                # message log here
                echo "echo \"${IP}:${port}\" | httpx -silent -H \"Host: ${unresponsive_vhost}\" -H \"User-Agent: ${user_agent}\"" >> "${log_execution_file}"
                httpx_unresponsive_size=$(echo "${IP}:${port}" | httpx -silent -H "Host: ${unresponsive_vhost}" -H "User-Agent: ${user_agent}" -content-length -hash md5 2>> "${log_execution_file}" | awk '{print $2}' | sed 's/\[// ; s/\]//')
                httpx_unresponsive_hash=$(echo "${IP}:${port}" | httpx -silent -H "Host: ${unresponsive_vhost}" -H "User-Agent: ${user_agent}" -content-length -hash md5 2>> "${log_execution_file}" | awk '{print $3}' | sed 's/\[// ; s/\]//')

                for vhost in "$(cat ${vhost_name_file})"; do
                    user_agent=$(get_user_agent)
                    # curl
                    echo "curl \"${curl_options[@]}\" -L -H \"User-Agent: ${user_agent}\" -H \"Host: ${vhost}\" \"http://${IP}:${port}\"" >> "${log_execution_file}"
                    curl_vhost_content=$(curl "${curl_options[@]}" -L -H "User-Agent: ${user_agent}" -H "Host: ${vhost}" "http://${IP}:${port}" 2>> "${log_execution_file}")
                    curl_vhost_size=$(echo "${curl_vhost_content}" | wc -c)
                    curl_vhost_hash=$(echo "${curl_vhost_content}" | md5sum | awk '{print $1}')
                    if [[ "${curl_unresponsive_size}" != "${curl_vhost_size}"  && "${curl_unresponsive_hash}" != "${curl_vhost_hash}" ]]; then
                        echo -e "${vhost}\t${IP}:${port}" >> "${tmp_dir}/vhost_subdomains.tmp"
                    fi
                    # httpx
                    echo "echo \"${IP}:${port}\" | httpx -silent -H \"Host: ${vhost}\" -H \"User-Agent: ${user_agent}\"" >> "${log_execution_file}"
                    httpx_vhost_size=$(echo "${IP}:${port}" | httpx -silent -H "Host: ${vhost}" -H "User-Agent: ${user_agent}" -content-length -hash md5 2>> "${log_execution_file}" | awk '{print $2}' | sed 's/\[// ; s/\]//')
                    httpx_vhost_md5=$(echo "${IP}:${port}" | httpx -silent -H "Host: ${vhost}" -H "User-Agent: ${user_agent}" -content-length -hash md5 2>> "${log_execution_file}" | awk '{print $3}' | sed 's/\[// ; s/\]//')
                    if [[ "${httpx_unresponsive_size}" != "${httpx_vhost_size}" && "${httpx_unresponsive_hash}" != "${httpx_vhost_hash}" ]]; then
                        echo -e "${vhost}\t${IP}:${port}" >> "${tmp_dir}/vhost_subdomains.tmp"
                    fi
                done
            done
        done
        if [[ -s "${tmp_dir}/vhost_subdomains.tmp" ]]; then
            sort -u -o "${report_dir}/vhost_subdomains.txt" "${tmp_dir}/vhost_subdomains.tmp"
        fi
        echo "Done!"
    else
        echo "Fail!"
    fi
}
