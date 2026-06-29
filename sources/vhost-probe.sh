#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * vhost_probe                                           #
#                                                           #
#############################################################
#
# Complementary to vhost_check() in sources/vhost-check.sh.
# vhost_check() probes unresolved subdomains against live IPs
# discovered during recon. vhost_probe() probes a wordlist of
# common vhost names against all real target IPs (infra_ipv4.txt),
# running after infra_data() so it has the full IP surface.
#
# A per-IP baseline is computed using a random hostname that
# should never resolve, mirroring vhost_check_pair()'s approach.
#
# Usage: vhost_probe <ip_file>
#   ip_file — one IPv4 per line (typically report_dir/infra_ipv4.txt)
#
#############################################################

vhost_probe(){
    local vhost_probe_ip_file="${1}"
    if [[ ! -s "${vhost_probe_ip_file}" ]]; then
        return 0
    fi
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing vhost probe... "
    : > "${tmp_dir}/vhost_probe_output.txt"
    # Word list lives at ${collector_vhost_probe_words} (configured in
    # collector.cfg, default: support/runtime/wordlists/vhost-probe-names.txt).
    # One name per line; blank lines and lines starting with '#' are ignored
    # so the file can carry section comments.
    local vhost_probe_words=()
    if [[ -s "${collector_vhost_probe_words}" ]]; then
        mapfile -t vhost_probe_words < <(grep -Ev '^[[:space:]]*(#|$)' "${collector_vhost_probe_words}")
    fi
    if [[ "${#vhost_probe_words[@]}" -eq 0 ]]; then
        echo "Fail! (wordlist missing or empty: ${collector_vhost_probe_words})"
        return 0
    fi
    local vhost_probe_max_workers="${vhost_check_processes:-8}"
    local vhost_probe_pids=()
    local vhost_probe_pid vhost_probe_alive_pids=()

    # Worker probes a single (IP, port, word) triple.
    # Args: $1=IP  $2=port  $3=word  $4=baseline_status  $5=baseline_len
    _vhost_probe_worker(){
        local vp_ip="${1}"
        local vp_port="${2}"
        local vp_word="${3}"
        local vp_baseline_status="${4}"
        local vp_baseline_len="${5}"
        local vp_host="${vp_word}.${domain}"
        local vp_ua vp_proto vp_url
        vp_ua="$(get_user_agent)"

        # Use https for known TLS ports, http for everything else.
        vp_proto="http"
        local p
        for p in "${webapp_tls_ports[@]}"; do
            [[ "${p}" == "${vp_port}" ]] && { vp_proto="https"; break; }
        done
        vp_url="${vp_proto}://${vp_ip}:${vp_port}"

        local vp_raw
        vp_raw="$(curl "${curl_options_fast[@]}" \
            -H "Host: ${vp_host}" \
            -H "User-agent: ${vp_ua}" \
            -o /dev/null -w "%{http_code} %{size_download}" \
            "${vp_url}" 2>/dev/null)"
        local vp_status vp_len vp_diff
        vp_status="$(echo "${vp_raw}" | awk '{print $1}')"
        vp_len="$(echo "${vp_raw}" | awk '{print $2}')"
        [[ -z "${vp_len}" ]] && vp_len=0
        vp_diff=$(( vp_len - vp_baseline_len ))
        [[ "${vp_diff}" -lt 0 ]] && vp_diff=$(( vp_diff * -1 ))
        if [[ "${vp_status}" != "${vp_baseline_status}" || "${vp_diff}" -gt 200 ]]; then
            echo -e "\nvhost hit: ${vp_host} on ${vp_ip}:${vp_port} (${vp_status}, ${vp_len}B)" >> "${log_execution_file}"
            echo "${vp_host}" >> "${tmp_dir}/vhost_probe_output.txt"
        fi
    }

    while IFS= read -r vhost_probe_ip; do
        [[ -z "${vhost_probe_ip}" ]] && continue
        vhost_probe_ip="$(echo "${vhost_probe_ip}" | grep -Eo "${IPv4_regex}")"
        [[ -z "${vhost_probe_ip}" ]] && continue

        # Compute a fresh per-(IP, port) baseline using a random hostname.
        local vhost_probe_rand_host
        vhost_probe_rand_host="$(tr -dc 'a-z' </dev/urandom | fold -w 12 | head -n1).${domain}"
        unset user_agent
        user_agent="$(get_user_agent)"

        local vhost_probe_port
        for vhost_probe_port in "${webapp_port_detect[@]}"; do
            local bp_proto="http"
            local p2
            for p2 in "${webapp_tls_ports[@]}"; do
                [[ "${p2}" == "${vhost_probe_port}" ]] && { bp_proto="https"; break; }
            done
            local bp_url="${bp_proto}://${vhost_probe_ip}:${vhost_probe_port}"
            echo -e "\ncurl ${curl_options_fast[@]} -H \"Host: ${vhost_probe_rand_host}\" -H \"User-agent: ${user_agent}\" -o /dev/null -w \"%{http_code} %{size_download}\" \"${bp_url}\"" >> "${log_execution_file}"
            local vhost_probe_baseline_raw
            vhost_probe_baseline_raw="$(curl "${curl_options_fast[@]}" \
                -H "Host: ${vhost_probe_rand_host}" \
                -H "User-agent: ${user_agent}" \
                -o /dev/null -w "%{http_code} %{size_download}" \
                "${bp_url}" 2>/dev/null)"
            local vhost_probe_baseline_status vhost_probe_baseline_len
            vhost_probe_baseline_status="$(echo "${vhost_probe_baseline_raw}" | awk '{print $1}')"
            vhost_probe_baseline_len="$(echo "${vhost_probe_baseline_raw}" | awk '{print $2}')"
            [[ -z "${vhost_probe_baseline_len}" ]] && vhost_probe_baseline_len=0

        for vhost_probe_word in "${vhost_probe_words[@]}"; do
            # Reap finished workers
            vhost_probe_alive_pids=()
            for vhost_probe_pid in "${vhost_probe_pids[@]}"; do
                kill -0 "${vhost_probe_pid}" 2>/dev/null && vhost_probe_alive_pids+=("${vhost_probe_pid}")
            done
            vhost_probe_pids=("${vhost_probe_alive_pids[@]}")
            # Block while at capacity
            while [[ "${#vhost_probe_pids[@]}" -ge "${vhost_probe_max_workers}" ]]; do
                sleep 0.5
                vhost_probe_alive_pids=()
                for vhost_probe_pid in "${vhost_probe_pids[@]}"; do
                    kill -0 "${vhost_probe_pid}" 2>/dev/null && vhost_probe_alive_pids+=("${vhost_probe_pid}")
                done
                vhost_probe_pids=("${vhost_probe_alive_pids[@]}")
            done
            _vhost_probe_worker "${vhost_probe_ip}" "${vhost_probe_port}" "${vhost_probe_word}" \
                "${vhost_probe_baseline_status}" "${vhost_probe_baseline_len}" &
            vhost_probe_pids+=("$!")
        done
        done  # end port loop
    done < "${vhost_probe_ip_file}"

    # Wait for remaining workers
    for vhost_probe_pid in "${vhost_probe_pids[@]}"; do
        wait "${vhost_probe_pid}" 2>/dev/null
    done

    sort -u -o "${tmp_dir}/vhost_probe_output.txt" "${tmp_dir}/vhost_probe_output.txt" 2>/dev/null
    echo "Done!"
}
