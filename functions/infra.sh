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

# Worker that probes a single (IP, port) pair against every dead vhost in
# vhost_name_file. Spawned in the background by vhost_check() so multiple
# pairs run in parallel up to vhost_check_processes.
#
# Args: $1=IP  $2=port  $3=vhost_name_file  $4=output file (per-worker)
_vhost_check_pair(){
    local _ip="$1"
    local _port="$2"
    local _vhost_name_file="$3"
    local _out_file="$4"

    local _proto="http"
    local _p
    # Switch to https:// for known TLS ports — probing them as plain HTTP
    # wastes the full max-time and produces meaningless bytes.
    for _p in "${webapp_tls_ports[@]}"; do
        if [[ "${_p}" == "${_port}" ]]; then
            _proto="https"
            break
        fi
    done
    local _url="${_proto}://${_ip}:${_port}"

    local _user_agent_baseline _user_agent_vhost
    _user_agent_baseline="$(get_user_agent)"
    # One UA for vhost requests is enough — regenerating per subdomain costs
    # a fork+read for /dev/urandom and adds nothing.
    _user_agent_vhost="$(get_user_agent)"

    local _baseline_host
    _baseline_host="$(tr -dc 'a-z' </dev/urandom | fold -w 10 | head -n1).${domain}"

    local _baseline_body="${tmp_dir}/vhost_baseline_body.${_ip}_${_port}.$$"
    local _vhost_body="${tmp_dir}/vhost_body.${_ip}_${_port}.$$"

    # ---- baseline (host that should never resolve to anything real) ----
    echo "curl ${curl_options_fast[@]} -H \"User-Agent: ${_user_agent_baseline}\" -H \"Host: ${_baseline_host}\" \"${_url}\"" >> "${log_execution_file}"
    local _curl_unresp_size _curl_unresp_hash
    _curl_unresp_size="$(curl "${curl_options_fast[@]}" \
        -H "User-Agent: ${_user_agent_baseline}" \
        -H "Host: ${_baseline_host}" \
        -o "${_baseline_body}" \
        -w '%{size_download}' \
        "${_url}" 2>> "${log_execution_file}")"
    _curl_unresp_hash="$(md5sum "${_baseline_body}" 2>/dev/null | awk '{print $1}')"

    echo "echo \"${_url}\" | httpx -silent -timeout 10 -retries 0 -H \"Host: ${_baseline_host}\" -H \"User-Agent: ${_user_agent_baseline}\" -content-length -hash md5" >> "${log_execution_file}"
    local _httpx_unresp_output _httpx_unresp_size _httpx_unresp_hash
    _httpx_unresp_output="$(echo "${_url}" | httpx -silent -timeout 10 -retries 0 \
        -H "Host: ${_baseline_host}" -H "User-Agent: ${_user_agent_baseline}" \
        -content-length -hash md5 2>> "${log_execution_file}")"
    _httpx_unresp_size="$(echo "${_httpx_unresp_output}" | awk '{print $2}' | sed 's/\[// ; s/\]//')"
    _httpx_unresp_hash="$(echo "${_httpx_unresp_output}" | awk '{print $3}' | sed 's/\[// ; s/\]//')"

    # ---- per-vhost probes ----
    # seen_responses is local to this worker (per-process associative array)
    # to dedupe within the (IP, port) scope. Final cross-pair dedupe happens
    # after all workers join via sort -u.
    local -A seen_responses
    local vhost
    local _curl_vhost_size _curl_vhost_hash
    local _httpx_vhost_output _httpx_vhost_size _httpx_vhost_hash
    local _curl_diff _httpx_diff _confidence _combo_key

    while IFS= read -r vhost; do
        [[ -z "${vhost}" ]] && continue

        # curl with the candidate vhost as Host header.
        echo "curl ${curl_options_fast[@]} -H \"User-Agent: ${_user_agent_vhost}\" -H \"Host: ${vhost}\" \"${_url}\"" >> "${log_execution_file}"
        _curl_vhost_size="$(curl "${curl_options_fast[@]}" \
            -H "User-Agent: ${_user_agent_vhost}" \
            -H "Host: ${vhost}" \
            -o "${_vhost_body}" \
            -w '%{size_download}' \
            "${_url}" 2>> "${log_execution_file}")"
        _curl_vhost_hash="$(md5sum "${_vhost_body}" 2>/dev/null | awk '{print $1}')"

        echo "echo \"${_url}\" | httpx -silent -timeout 10 -retries 0 -H \"Host: ${vhost}\" -H \"User-Agent: ${_user_agent_vhost}\" -content-length -hash md5" >> "${log_execution_file}"
        _httpx_vhost_output="$(echo "${_url}" | httpx -silent -timeout 10 -retries 0 \
            -H "Host: ${vhost}" -H "User-Agent: ${_user_agent_vhost}" \
            -content-length -hash md5 2>> "${log_execution_file}")"
        _httpx_vhost_size="$(echo "${_httpx_vhost_output}" | awk '{print $2}' | sed 's/\[// ; s/\]//')"
        _httpx_vhost_hash="$(echo "${_httpx_vhost_output}" | awk '{print $3}' | sed 's/\[// ; s/\]//')"

        _curl_diff="no"
        if [[ "${_curl_unresp_size}" != "${_curl_vhost_size}" && \
              "${_curl_unresp_hash}" != "${_curl_vhost_hash}" ]]; then
            _curl_diff="yes"
        fi

        _httpx_diff="no"
        if [[ "${_httpx_unresp_size}" != "${_httpx_vhost_size}" && \
              "${_httpx_unresp_hash}" != "${_httpx_vhost_hash}" ]]; then
            _httpx_diff="yes"
        fi

        # Confidence: STRONG when both curl and httpx see a different page
        # for this Host than for the baseline; WEAK when only one of them
        # does. WEAK results land in a separate file so the operator can
        # review them without polluting the high-signal report.
        _confidence=""
        if [[ "${_curl_diff}" == "yes" && "${_httpx_diff}" == "yes" ]]; then
            _confidence="STRONG"
        elif [[ "${_curl_diff}" == "yes" || "${_httpx_diff}" == "yes" ]]; then
            _confidence="WEAK"
        fi

        if [[ -n "${_confidence}" ]]; then
            _combo_key="${vhost}_${_httpx_vhost_hash}_${_curl_vhost_hash}"
            if [[ -z "${seen_responses[$_combo_key]}" ]]; then
                printf '%s\t%s\tSize: %s\tHash: %s\t%s\n' \
                    "${vhost}" "${_ip}:${_port}" \
                    "${_httpx_vhost_size}" "${_httpx_vhost_hash}" \
                    "${_confidence}" \
                    >> "${_out_file}"
                seen_responses[$_combo_key]=1
            fi
        fi
    done < "${_vhost_name_file}"

    rm -f "${_baseline_body}" "${_vhost_body}"
}

vhost_check(){
    # ---- locals ----------------------------------------------------------
    local _vhost_name_file="$1"
    local _vhost_ip_file="$2"
    local _max_workers="${vhost_check_processes:-8}"
    local _strong_out="${tmp_dir}/vhost_subdomains_strong.tmp"
    local _weak_out="${tmp_dir}/vhost_subdomains_weak.tmp"
    local IP port _per_worker_out
    local -a _worker_pids=()
    local _pid _alive
    # ----------------------------------------------------------------------

    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Looking for vhost with dead subdomains... "
    echo -e "\n" >> "${log_execution_file}"

    if [[ -s "${_vhost_ip_file}" && -s "${report_dir}/infra_ipv4.txt" ]]; then
        : > "${_strong_out}"
        : > "${_weak_out}"

        # Fan out: one worker per (IP, port) pair, capped at _max_workers.
        # Each worker writes to its own .tmp so there's no append race.
        # Backpressure is enforced by tracking PIDs we spawned (not by
        # pgrep — that would also count unrelated background jobs).
        while IFS= read -r IP; do
            [[ -z "${IP}" ]] && continue
            for port in "${webapp_port_detect[@]}"; do
                # Reap dead workers and block while at capacity.
                while :; do
                    _alive=()
                    for _pid in "${_worker_pids[@]}"; do
                        if kill -0 "${_pid}" 2>/dev/null; then
                            _alive+=("${_pid}")
                        fi
                    done
                    _worker_pids=("${_alive[@]}")
                    [[ "${#_worker_pids[@]}" -lt "${_max_workers}" ]] && break
                    sleep 1
                done

                _per_worker_out="${tmp_dir}/vhost_pair_${IP}_${port}_$$.tmp"
                _vhost_check_pair "${IP}" "${port}" "${_vhost_name_file}" "${_per_worker_out}" &
                _worker_pids+=("$!")
            done
        done < "${_vhost_ip_file}"

        # Wait for every worker we spawned (and only those).
        for _pid in "${_worker_pids[@]}"; do
            wait "${_pid}" 2>/dev/null
        done

        # Aggregate per-worker outputs into strong/weak buckets.
        local _line _conf
        for _per_worker_out in "${tmp_dir}"/vhost_pair_*_$$.tmp; do
            [[ -s "${_per_worker_out}" ]] || continue
            while IFS= read -r _line; do
                _conf="${_line##*$'\t'}"
                if [[ "${_conf}" == "STRONG" ]]; then
                    echo "${_line}" >> "${_strong_out}"
                else
                    echo "${_line}" >> "${_weak_out}"
                fi
            done < "${_per_worker_out}"
            rm -f "${_per_worker_out}"
        done

        if [[ -s "${_strong_out}" ]]; then
            sort -u -o "${report_dir}/vhost_subdomains.txt" "${_strong_out}"
        fi
        if [[ -s "${_weak_out}" ]]; then
            sort -u -o "${report_dir}/vhost_subdomains_weak.txt" "${_weak_out}"
        fi
        echo "Done!"
    else
        echo "Fail!"
    fi
}
