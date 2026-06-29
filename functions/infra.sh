#!/bin/bash
#############################################################
# Getting information about infrastructure (IPs, ASN, CIDR) #
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * infra_data                                            #
#                                                           #
# nmap_scan / shodan_scan moved to scans/{nmap,shodan}.sh.  #
#############################################################

infra_data(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Getting information about infrastructure... "
    if [ -s "${report_dir}/domains_external_ipv4.txt" ]; then
        echo -en "\n${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Getting AS information... "
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
            # Generalised owner fingerprint (report C-10): the previous code only
            # checked `ownerid:` which is specific to whois.registro.br (.br ccTLD).
            # For .com / .net / .org / .io / ... that field is absent and the
            # whole AS-block sweep silently did nothing. Try several common
            # registry-owner fields in order of specificity, and pick the first
            # non-empty value.
            ownerid=""
            whois_domain_out="$(whois "${domain}" 2>/dev/null)"
            for ownerid_field in "ownerid" "OrgName" "org-name" "Registrant Organization" "Organization" "netname"; do
                ownerid_candidate="$(echo "${whois_domain_out}" \
                    | grep -Ei "^[[:space:]]*${ownerid_field}[[:space:]]*:" \
                    | head -1 | sed -E 's/^[^:]+:[[:space:]]*//' \
                    | sed -E 's/[[:space:]]+$//')"
                # Require ≥ 5 chars to avoid trash tokens like 'Inc', 'NA', '-'.
                if [[ -n "${ownerid_candidate}" && "${#ownerid_candidate}" -ge 5 ]]; then
                    ownerid="${ownerid_candidate}"
                    break
                fi
            done
            unset whois_domain_out ownerid_field ownerid_candidate

            for IP in $(grep -Ev "Google|Microsoft|Azure|AWS|Amazon|Cloudflare" "${report_dir}/infra_as.txt" | tail -n+2 | awk '{print $3}'); do
                if [[ -n "${ownerid}" ]]; then
                    # Capture once — reuse for both the ownership check and CIDR extraction.
                    ib_whois="$(whois "${IP}" 2>/dev/null)"
                    # Case-insensitive, literal match — registries vary in casing
                    # and the ownerid may include regex metacharacters.
                    if echo "${ib_whois}" | grep -qiF "${ownerid}"; then
                        sleep 3
                        # IPv4 block
                        echo "${ib_whois}" | grep -E "${IP%%.*}.*\/[0-9]{2}$" >> "${tmp_dir}/infra_blocks.tmp"
                        # IPv6 block
                        # ?
                    fi
                    unset ib_whois
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
        echo -e "File ${report_dir}/domains_external_ipv4.txt does not exist or is empty!" | notify "${notify_pc_args[@]}" "${notify_options[@]}" -id "${notify_recon_channel}" > /dev/null 2>&1
        message "${domain}" failed
    fi
}

# nmap_scan and shodan_scan were moved to scans/nmap.sh and scans/shodan.sh
# so the IP-surface scanners live next to nuclei_scan (web vuln scan) in
# one dedicated directory. The collector main sources scans/*.sh after
# functions/*.sh so the call sites in domains_recon.sh keep working.
