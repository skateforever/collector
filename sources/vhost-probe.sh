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

# Quick TCP-connect probe to discard ports that don't answer at all.
# Returns 0 if the port is open, 1 otherwise.
vhost_port_alive(){
    local vpa_ip="$1" vpa_port="$2" vpa_timeout="${vhost_prefilter_timeout:-3}"
    local vpa_proto="http"
    local vpa_p
    for vpa_p in "${webapp_tls_ports[@]}"; do
        [[ "${vpa_p}" == "${vpa_port}" ]] && { vpa_proto="https"; break; }
    done
    curl -k -s --connect-timeout "${vpa_timeout}" --max-time "${vpa_timeout}" \
        -o /dev/null -w "%{http_code}" "${vpa_proto}://${vpa_ip}:${vpa_port}" 2>/dev/null | grep -qE '^[1-5][0-9]{2}$'
}

# Fast vhost probe using ffuf's native vhost mode.
# Replaces the bash curl loop with a single ffuf invocation per (IP, port).
# Requires: ffuf in PATH, vhost_use_ffuf=yes in collector.cfg.
vhost_probe_ffuf(){
    local ffuf_ip_file="$1"
    local ffuf_threads_vp="${vhostffuf_threads_vp:-50}"
    local ffuf_wordlist="${collector_vhost_probe_words}"

    if [[ ! -s "${ffuf_wordlist}" ]]; then
        echo "Fail! (wordlist missing: ${ffuf_wordlist})"
        return 0
    fi

    : > "${tmp_dir}/vhost_probe_output.txt"
    local ffuf_ip ffuf_port ffuf_proto ffuf_url
    local ffuf_baseline_size ffuf_rand_host ffuf_out tls_p

    while IFS= read -r ffuf_ip; do
        [[ -z "${ffuf_ip}" ]] && continue
        ffuf_ip="$(echo "${ffuf_ip}" | grep -Eo "${IPv4_regex}")"
        [[ -z "${ffuf_ip}" ]] && continue

        local -a vp_ports=()
        if [[ "${#vhost_port_detect[@]}" -gt 0 ]]; then
            vp_ports=("${vhost_port_detect[@]}")
        else
            vp_ports=("${webapp_port_detect[@]}")
        fi

        for ffuf_port in "${vp_ports[@]}"; do
            ffuf_proto="http"
            for tls_p in "${webapp_tls_ports[@]}"; do
                [[ "${tls_p}" == "${ffuf_port}" ]] && { ffuf_proto="https"; break; }
            done
            ffuf_url="${ffuf_proto}://${ffuf_ip}:${ffuf_port}"

            # Get baseline response size with random hostname
            ffuf_rand_host="$(tr -dc 'a-z' </dev/urandom | fold -w 12 | head -n1).${domain}"
            ffuf_baseline_size="$(curl -k -s --connect-timeout 3 --max-time 5 \
                -H "Host: ${ffuf_rand_host}" \
                -o /dev/null -w "%{size_download}" \
                "${ffuf_url}" 2>/dev/null)"

            # Skip port if no response
            [[ -z "${ffuf_baseline_size}" || "${ffuf_baseline_size}" == "0" ]] && continue

            ffuf_out="${tmp_dir}/ffuf_vhost_${ffuf_ip}_${ffuf_port}.tmp"

            # ffuf vhost mode: FUZZ is replaced with each wordlist entry
            # -fs filters out responses matching baseline size (false positives)
            # -t threads, -timeout per-request timeout
            echo "ffuf -u ${ffuf_url} -H \"Host: FUZZ.${domain}\" -w ${ffuf_wordlist} -fs ${ffuf_baseline_size} -t ${ffuf_threads_vp}" >> "${log_execution_file}"
            ffuf -u "${ffuf_url}" \
                -H "Host: FUZZ.${domain}" \
                -w "${ffuf_wordlist}" \
                -fs "${ffuf_baseline_size}" \
                -t "${ffuf_threads_vp}" \
                -timeout 5 \
                -s \
                -noninteractive \
                -mc all \
                -o "${ffuf_out}" \
                -of csv 2>> "${log_execution_file}"

            # Parse ffuf CSV output: extract matched hostnames
            if [[ -s "${ffuf_out}" ]]; then
                # ffuf CSV: first line is header, columns vary but input field is always present
                tail -n+2 "${ffuf_out}" | while IFS=',' read -r x1 x2 x3 x4 x5 input rest; do
                    [[ -n "${input}" && "${input}" != "input" ]] && echo "${input}.${domain}"
                done >> "${tmp_dir}/vhost_probe_output.txt"
            fi
            rm -f "${ffuf_out}"
        done
    done < "${ffuf_ip_file}"

    sort -u -o "${tmp_dir}/vhost_probe_output.txt" "${tmp_dir}/vhost_probe_output.txt" 2>/dev/null
}

vhost_probe(){
    local vhost_probe_ip_file="${1}"
    if [[ ! -s "${vhost_probe_ip_file}" ]]; then
        return 0
    fi
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing vhost probe... "
    : > "${tmp_dir}/vhost_probe_output.txt"

    # Fast path: use ffuf if available and enabled.
    if [[ "${vhost_use_ffuf}" == "yes" ]] && command -v ffuf &>/dev/null; then
        vhost_probe_ffuf "${vhost_probe_ip_file}"
        echo "Done! (ffuf mode)"
        return 0
    fi

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
    local vhost_probe_max_workers="${vhost_probe_processes:-50}"
    local -a vp_probe_ports=()
    if [[ "${#vhost_port_detect[@]}" -gt 0 ]]; then
        vp_probe_ports=("${vhost_port_detect[@]}")
    else
        vp_probe_ports=("${webapp_port_detect[@]}")
    fi
    local vhost_probe_pids=()
    local vhost_probe_pid vhost_probe_alive_pids=()
    local -a vp_curl_opts=()
    if [[ "${#vhost_curl_options[@]}" -gt 0 ]]; then
        vp_curl_opts=("${vhost_curl_options[@]}")
    else
        vp_curl_opts=("${curl_options_fast[@]}")
    fi

    # Batch worker: probes a slice of the wordlist for a single (IP, port) pair.
    # Args: $1=IP $2=port $3=baseline_status $4=baseline_len $5..=words
    vhost_probe_batch_worker(){
        local bp_ip="$1" bp_port="$2" bp_baseline_status="$3" bp_baseline_len="$4"
        shift 4
        local bp_proto="http" bp_url bp_ua bp_word bp_host
        local bp_raw bp_status bp_len bp_diff
        local tls_p

        for tls_p in "${webapp_tls_ports[@]}"; do
            [[ "${tls_p}" == "${bp_port}" ]] && { bp_proto="https"; break; }
        done
        bp_url="${bp_proto}://${bp_ip}:${bp_port}"
        bp_ua="$(get_user_agent)"

        for bp_word in "$@"; do
            bp_host="${bp_word}.${domain}"
            bp_raw="$(curl "${vp_curl_opts[@]}" \
                -H "Host: ${bp_host}" \
                -H "User-agent: ${bp_ua}" \
                -o /dev/null -w "%{http_code} %{size_download}" \
                "${bp_url}" 2>/dev/null)"
            bp_status="${bp_raw%% *}"
            bp_len="${bp_raw##* }"
            [[ -z "${bp_len}" ]] && bp_len=0
            bp_diff=$(( bp_len - bp_baseline_len ))
            [[ "${bp_diff}" -lt 0 ]] && bp_diff=$(( -bp_diff ))
            if [[ "${bp_status}" != "${bp_baseline_status}" || "${bp_diff}" -gt 200 ]]; then
                echo "${bp_host}" >> "${tmp_dir}/vhost_probe_worker_${bp_ip}_${bp_port}_$$.tmp"
            fi
        done
    }

    local batch_size="${vhost_probe_batch_size:-50}"

    while IFS= read -r vhost_probe_ip; do
        [[ -z "${vhost_probe_ip}" ]] && continue
        vhost_probe_ip="$(echo "${vhost_probe_ip}" | grep -Eo "${IPv4_regex}")"
        [[ -z "${vhost_probe_ip}" ]] && continue

        local vhost_probe_rand_host
        vhost_probe_rand_host="$(tr -dc 'a-z' </dev/urandom | fold -w 12 | head -n1).${domain}"
        unset user_agent
        user_agent="$(get_user_agent)"

        local vhost_probe_port
        for vhost_probe_port in "${vp_probe_ports[@]}"; do
            vhost_port_alive "${vhost_probe_ip}" "${vhost_probe_port}" || continue
            local bp_proto="http"
            local p2
            for p2 in "${webapp_tls_ports[@]}"; do
                [[ "${p2}" == "${vhost_probe_port}" ]] && { bp_proto="https"; break; }
            done
            local bp_url="${bp_proto}://${vhost_probe_ip}:${vhost_probe_port}"
            local vhost_probe_baseline_raw
            vhost_probe_baseline_raw="$(curl "${vp_curl_opts[@]}" \
                -H "Host: ${vhost_probe_rand_host}" \
                -H "User-agent: ${user_agent}" \
                -o /dev/null -w "%{http_code} %{size_download}" \
                "${bp_url}" 2>/dev/null)"
            local vhost_probe_baseline_status vhost_probe_baseline_len
            vhost_probe_baseline_status="${vhost_probe_baseline_raw%% *}"
            vhost_probe_baseline_len="${vhost_probe_baseline_raw##* }"
            [[ -z "${vhost_probe_baseline_len}" ]] && vhost_probe_baseline_len=0

            # Early exit: if baseline gets no response, skip this port.
            if [[ "${vhost_probe_baseline_status}" == "000" || -z "${vhost_probe_baseline_status}" ]]; then
                continue
            fi

            # Dispatch batches of words
            local batch=() bidx=0
            for vhost_probe_word in "${vhost_probe_words[@]}"; do
                batch+=("${vhost_probe_word}")
                ((bidx += 1))
                if [[ "${bidx}" -ge "${batch_size}" ]]; then
                    # Reap finished workers and throttle
                    vhost_probe_alive_pids=()
                    for vhost_probe_pid in "${vhost_probe_pids[@]}"; do
                        kill -0 "${vhost_probe_pid}" 2>/dev/null && vhost_probe_alive_pids+=("${vhost_probe_pid}")
                    done
                    vhost_probe_pids=("${vhost_probe_alive_pids[@]}")
                    while [[ "${#vhost_probe_pids[@]}" -ge "${vhost_probe_max_workers}" ]]; do
                        sleep 0.3
                        vhost_probe_alive_pids=()
                        for vhost_probe_pid in "${vhost_probe_pids[@]}"; do
                            kill -0 "${vhost_probe_pid}" 2>/dev/null && vhost_probe_alive_pids+=("${vhost_probe_pid}")
                        done
                        vhost_probe_pids=("${vhost_probe_alive_pids[@]}")
                    done
                    vhost_probe_batch_worker "${vhost_probe_ip}" "${vhost_probe_port}" \
                        "${vhost_probe_baseline_status}" "${vhost_probe_baseline_len}" "${batch[@]}" &
                    vhost_probe_pids+=("$!")
                    batch=()
                    bidx=0
                fi
            done
            # Dispatch remaining words
            if [[ "${#batch[@]}" -gt 0 ]]; then
                vhost_probe_alive_pids=()
                for vhost_probe_pid in "${vhost_probe_pids[@]}"; do
                    kill -0 "${vhost_probe_pid}" 2>/dev/null && vhost_probe_alive_pids+=("${vhost_probe_pid}")
                done
                vhost_probe_pids=("${vhost_probe_alive_pids[@]}")
                while [[ "${#vhost_probe_pids[@]}" -ge "${vhost_probe_max_workers}" ]]; do
                    sleep 0.3
                    vhost_probe_alive_pids=()
                    for vhost_probe_pid in "${vhost_probe_pids[@]}"; do
                        kill -0 "${vhost_probe_pid}" 2>/dev/null && vhost_probe_alive_pids+=("${vhost_probe_pid}")
                    done
                    vhost_probe_pids=("${vhost_probe_alive_pids[@]}")
                done
                vhost_probe_batch_worker "${vhost_probe_ip}" "${vhost_probe_port}" \
                    "${vhost_probe_baseline_status}" "${vhost_probe_baseline_len}" "${batch[@]}" &
                vhost_probe_pids+=("$!")
            fi
        done  # end port loop
    done < "${vhost_probe_ip_file}"

    # Wait for remaining workers
    for vhost_probe_pid in "${vhost_probe_pids[@]}"; do
        wait "${vhost_probe_pid}" 2>/dev/null
    done

    # Merge per-worker outputs and deduplicate
    cat "${tmp_dir}"/vhost_probe_worker_*.tmp >> "${tmp_dir}/vhost_probe_output.txt" 2>/dev/null
    rm -f "${tmp_dir}"/vhost_probe_worker_*.tmp
    sort -u -o "${tmp_dir}/vhost_probe_output.txt" "${tmp_dir}/vhost_probe_output.txt" 2>/dev/null
    echo "Done!"
}
