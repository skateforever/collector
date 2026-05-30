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
        if [ -s "${report_dir}/domains_external_ipv4.txt" ] ; then
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
        echo -e "File ${report_dir}/domains_external_ipv4.txt does not exist or is empty!" | notify -nc -silent -id "${notify_recon_channel}" > /dev/null 2>&1
        message "${domain}" failed
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
            for IP in $(cat "${report_dir}/infra_ipv4.txt"); do
                echo "shodan scan submit ${IP} > ${shodan_dir}/shodan_scan.txt" >> "${log_execution_file}"
                "shodan" scan submit "${IP}" > "${shodan_dir}/shodan_scan.txt" 2>> "${log_execution_file}" &
            done
        fi
        echo "Done!"
    fi
}

# Worker that probes a single (IP, port) pair against every dead vhost.
# Spawned in background by vhost_check() so pairs run in parallel.
# Args: $1=IP $2=port $3=vhost_name_file $4=output file (per-worker)
vhost_check_pair(){
    local ip="$1"
    local port="$2"
    local vhost_name_file="$3"
    local out_file="$4"
    local proto="http"
    local p

    # Switch to https:// for known TLS ports.
    for p in "${webapp_tls_ports[@]}"; do
        [[ "${p}" == "${port}" ]] && { proto="https"; break; }
    done
    local url="${proto}://${ip}:${port}"

    local user_agent_baseline user_agent_vhost
    user_agent_baseline="$(get_user_agent)"
    user_agent_vhost="$(get_user_agent)"

    local baseline_host
    baseline_host="$(tr -dc 'a-z' </dev/urandom | fold -w 10 | head -n1).${domain}"

    local baseline_body="${tmp_dir}/vhost_baseline_body.${ip}_${port}.$$"
    local vhost_body="${tmp_dir}/vhost_body.${ip}_${port}.$$"

    # Baseline (host that should never resolve to anything real)
    echo "curl ${curl_options_fast[@]} -H \"User-Agent: ${user_agent_baseline}\" -H \"Host: ${baseline_host}\" \"${url}\"" >> "${log_execution_file}"
    local curl_unresp_size curl_unresp_hash
    curl_unresp_size="$(curl "${curl_options_fast[@]}" -H "User-Agent: ${user_agent_baseline}" -H "Host: ${baseline_host}" -o "${baseline_body}" -w '%{size_download}' "${url}" 2>> "${log_execution_file}")"
    curl_unresp_hash="$(md5sum "${baseline_body}" 2>/dev/null | awk '{print $1}')"

    echo "echo \"${url}\" | httpx -silent -timeout 10 -retries 0 -H \"Host: ${baseline_host}\" -H \"User-Agent: ${user_agent_baseline}\" -content-length -hash md5" >> "${log_execution_file}"
    local httpx_unresp_output httpx_unresp_size httpx_unresp_hash
    httpx_unresp_output="$(echo "${url}" | httpx -silent -timeout 10 -retries 0 -H "Host: ${baseline_host}" -H "User-Agent: ${user_agent_baseline}" -content-length -hash md5 2>> "${log_execution_file}")"
    httpx_unresp_size="$(echo "${httpx_unresp_output}" | awk '{print $2}' | sed 's/\[// ; s/\]//')"
    httpx_unresp_hash="$(echo "${httpx_unresp_output}" | awk '{print $3}' | sed 's/\[// ; s/\]//')"

    # Per-vhost probes. seen_responses dedupes within this worker.
    local -A seen_responses
    local vhost
    local curl_vhost_size curl_vhost_hash
    local httpx_vhost_output httpx_vhost_size httpx_vhost_hash
    local curl_diff httpx_diff confidence combo_key

    while IFS= read -r vhost; do
        [[ -z "${vhost}" ]] && continue

        echo "curl ${curl_options_fast[@]} -H \"User-Agent: ${user_agent_vhost}\" -H \"Host: ${vhost}\" \"${url}\"" >> "${log_execution_file}"
        curl_vhost_size="$(curl "${curl_options_fast[@]}" -H "User-Agent: ${user_agent_vhost}" -H "Host: ${vhost}" -o "${vhost_body}" -w '%{size_download}' "${url}" 2>> "${log_execution_file}")"
        curl_vhost_hash="$(md5sum "${vhost_body}" 2>/dev/null | awk '{print $1}')"

        echo "echo \"${url}\" | httpx -silent -timeout 10 -retries 0 -H \"Host: ${vhost}\" -H \"User-Agent: ${user_agent_vhost}\" -content-length -hash md5" >> "${log_execution_file}"
        httpx_vhost_output="$(echo "${url}" | httpx -silent -timeout 10 -retries 0 -H "Host: ${vhost}" -H "User-Agent: ${user_agent_vhost}" -content-length -hash md5 2>> "${log_execution_file}")"
        httpx_vhost_size="$(echo "${httpx_vhost_output}" | awk '{print $2}' | sed 's/\[// ; s/\]//')"
        httpx_vhost_hash="$(echo "${httpx_vhost_output}" | awk '{print $3}' | sed 's/\[// ; s/\]//')"

        curl_diff="no"
        [[ "${curl_unresp_size}" != "${curl_vhost_size}" && "${curl_unresp_hash}" != "${curl_vhost_hash}" ]] && curl_diff="yes"

        httpx_diff="no"
        [[ "${httpx_unresp_size}" != "${httpx_vhost_size}" && "${httpx_unresp_hash}" != "${httpx_vhost_hash}" ]] && httpx_diff="yes"

        # STRONG when both probes differ; WEAK when only one differs.
        confidence=""
        if [[ "${curl_diff}" == "yes" && "${httpx_diff}" == "yes" ]]; then
            confidence="STRONG"
        elif [[ "${curl_diff}" == "yes" || "${httpx_diff}" == "yes" ]]; then
            confidence="WEAK"
        fi

        if [[ -n "${confidence}" ]]; then
            combo_key="${vhost}_${httpx_vhost_hash}_${curl_vhost_hash}"
            if [[ -z "${seen_responses[$combo_key]}" ]]; then
                printf '%s\t%s\tSize: %s\tHash: %s\t%s\n' "${vhost}" "${ip}:${port}" "${httpx_vhost_size}" "${httpx_vhost_hash}" "${confidence}" >> "${out_file}"
                seen_responses[$combo_key]=1
            fi
        fi
    done < "${vhost_name_file}"

    rm -f "${baseline_body}" "${vhost_body}"
}

vhost_check(){
    local vhost_name_file="$1"
    local vhost_ip_file="$2"
    local max_workers="${vhost_check_processes:-8}"
    local strong_out="${tmp_dir}/vhost_subdomains_strong.tmp"
    local weak_out="${tmp_dir}/vhost_subdomains_weak.tmp"
    local IP port per_worker_out
    local -a worker_pids=()
    local pid alive

    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Looking for vhost with dead subdomains... "
    echo -e "\n" >> "${log_execution_file}"

    if [[ -s "${vhost_ip_file}" && -s "${report_dir}/infra_ipv4.txt" ]]; then
        : > "${strong_out}"
        : > "${weak_out}"

        # Fan out: one worker per (IP, port) pair, capped at max_workers.
        while IFS= read -r IP; do
            [[ -z "${IP}" ]] && continue
            for port in "${webapp_port_detect[@]}"; do
                # Reap dead workers and block while at capacity.
                while :; do
                    alive=()
                    for pid in "${worker_pids[@]}"; do
                        kill -0 "${pid}" 2>/dev/null && alive+=("${pid}")
                    done
                    worker_pids=("${alive[@]}")
                    [[ "${#worker_pids[@]}" -lt "${max_workers}" ]] && break
                    sleep 1
                done

                per_worker_out="${tmp_dir}/vhost_pair_${IP}_${port}_$$.tmp"
                vhost_check_pair "${IP}" "${port}" "${vhost_name_file}" "${per_worker_out}" &
                worker_pids+=("$!")
            done
        done < "${vhost_ip_file}"

        for pid in "${worker_pids[@]}"; do
            wait "${pid}" 2>/dev/null
        done

        # Aggregate per-worker outputs into strong/weak buckets.
        local line conf
        for per_worker_out in "${tmp_dir}"/vhost_pair_*_$$.tmp; do
            [[ -s "${per_worker_out}" ]] || continue
            while IFS= read -r line; do
                conf="${line##*$'\t'}"
                if [[ "${conf}" == "STRONG" ]]; then
                    echo "${line}" >> "${strong_out}"
                else
                    echo "${line}" >> "${weak_out}"
                fi
            done < "${per_worker_out}"
            rm -f "${per_worker_out}"
        done

        [[ -s "${strong_out}" ]] && sort -u -o "${report_dir}/vhost_subdomains.txt" "${strong_out}"
        [[ -s "${weak_out}" ]] && sort -u -o "${report_dir}/vhost_subdomains_weak.txt" "${weak_out}"
        echo "Done!"
    else
        echo "Fail!"
    fi
}
