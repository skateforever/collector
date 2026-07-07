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
_vhost_port_alive(){
    local _ip="$1" _port="$2" _timeout="${vhost_prefilter_timeout:-3}"
    local _proto="http"
    local _p
    for _p in "${webapp_tls_ports[@]}"; do
        [[ "${_p}" == "${_port}" ]] && { _proto="https"; break; }
    done
    curl -k -s --connect-timeout "${_timeout}" --max-time "${_timeout}" \
        -o /dev/null -w "%{http_code}" "${_proto}://${_ip}:${_port}" 2>/dev/null | grep -qE '^[1-5][0-9]{2}$'
}

# Fast vhost probe using ffuf's native vhost mode.
# Replaces the bash curl loop with a single ffuf invocation per (IP, port).
# Requires: ffuf in PATH, vhost_use_ffuf=yes in collector.cfg.
_vhost_probe_ffuf(){
    local _ffuf_ip_file="$1"
    local _ffuf_threads="${vhost_ffuf_threads:-50}"
    local _ffuf_wordlist="${collector_vhost_probe_words}"

    if [[ ! -s "${_ffuf_wordlist}" ]]; then
        echo "Fail! (wordlist missing: ${_ffuf_wordlist})"
        return 0
    fi

    : > "${tmp_dir}/vhost_probe_output.txt"
    local _ffuf_ip _ffuf_port _ffuf_proto _ffuf_url
    local _ffuf_baseline_size _ffuf_rand_host _ffuf_out _p

    while IFS= read -r _ffuf_ip; do
        [[ -z "${_ffuf_ip}" ]] && continue
        _ffuf_ip="$(echo "${_ffuf_ip}" | grep -Eo "${IPv4_regex}")"
        [[ -z "${_ffuf_ip}" ]] && continue

        local -a _vp_ports=()
        if [[ "${#vhost_port_detect[@]}" -gt 0 ]]; then
            _vp_ports=("${vhost_port_detect[@]}")
        else
            _vp_ports=("${webapp_port_detect[@]}")
        fi

        for _ffuf_port in "${_vp_ports[@]}"; do
            _ffuf_proto="http"
            for _p in "${webapp_tls_ports[@]}"; do
                [[ "${_p}" == "${_ffuf_port}" ]] && { _ffuf_proto="https"; break; }
            done
            _ffuf_url="${_ffuf_proto}://${_ffuf_ip}:${_ffuf_port}"

            # Get baseline response size with random hostname
            _ffuf_rand_host="$(tr -dc 'a-z' </dev/urandom | fold -w 12 | head -n1).${domain}"
            _ffuf_baseline_size="$(curl -k -s --connect-timeout 3 --max-time 5 \
                -H "Host: ${_ffuf_rand_host}" \
                -o /dev/null -w "%{size_download}" \
                "${_ffuf_url}" 2>/dev/null)"

            # Skip port if no response
            [[ -z "${_ffuf_baseline_size}" || "${_ffuf_baseline_size}" == "0" ]] && continue

            _ffuf_out="${tmp_dir}/ffuf_vhost_${_ffuf_ip}_${_ffuf_port}.tmp"

            # ffuf vhost mode: FUZZ is replaced with each wordlist entry
            # -fs filters out responses matching baseline size (false positives)
            # -t threads, -timeout per-request timeout
            echo "ffuf -u ${_ffuf_url} -H \"Host: FUZZ.${domain}\" -w ${_ffuf_wordlist} -fs ${_ffuf_baseline_size} -t ${_ffuf_threads}" >> "${log_execution_file}"
            ffuf -u "${_ffuf_url}" \
                -H "Host: FUZZ.${domain}" \
                -w "${_ffuf_wordlist}" \
                -fs "${_ffuf_baseline_size}" \
    # Fast path: use ffuf if available and enabled.
    if [[ "${vhost_use_ffuf}" == "yes" ]] && command -v ffuf &>/dev/null; then
        _vhost_probe_ffuf "${vhost_probe_ip_file}"
        echo "Done! (ffuf mode)"
        return 0
    fi

                -t "${_ffuf_threads}" \
                -timeout 5 \
                -s \
                -noninteractive \
                -mc all \
                -o "${_ffuf_out}" \
                -of csv 2>> "${log_execution_file}"

            # Parse ffuf CSV output: extract matched hostnames
            if [[ -s "${_ffuf_out}" ]]; then
                # ffuf CSV: first line is header, columns vary but input field is always present
                tail -n+2 "${_ffuf_out}" | while IFS=',' read -r _ _ _ _ _ input _rest; do
                    [[ -n "${input}" && "${input}" != "input" ]] && echo "${input}.${domain}"
                done >> "${tmp_dir}/vhost_probe_output.txt"
            fi
            rm -f "${_ffuf_out}"
        done
    done < "${_ffuf_ip_file}"

    sort -u -o "${tmp_dir}/vhost_probe_output.txt" "${tmp_dir}/vhost_probe_output.txt" 2>/dev/null
}

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
    local vhost_probe_max_workers="${vhost_probe_processes:-50}"
    local -a _vhost_ports=()
    if [[ "${#vhost_port_detect[@]}" -gt 0 ]]; then
        _vhost_ports=("${vhost_port_detect[@]}")
    else
        _vhost_ports=("${webapp_port_detect[@]}")
    fi
    local vhost_probe_pids=()
    local vhost_probe_pid vhost_probe_alive_pids=()
    local -a _vhost_curl_opts=()
    if [[ "${#vhost_curl_options[@]}" -gt 0 ]]; then
        _vhost_curl_opts=("${vhost_curl_options[@]}")
    else
        _vhost_curl_opts=("${curl_options_fast[@]}")
    fi

    # Batch worker: probes a slice of the wordlist for a single (IP, port) pair.
    # Args: $1=IP $2=port $3=baseline_status $4=baseline_len $5..=words
    _vhost_probe_batch_worker(){
        local _bp_ip="$1" _bp_port="$2" _bp_baseline_status="$3" _bp_baseline_len="$4"
        shift 4
        local _bp_proto="http" _bp_url _bp_ua _bp_word _bp_host
        local _bp_raw _bp_status _bp_len _bp_diff
        local _p

        for _p in "${webapp_tls_ports[@]}"; do
            [[ "${_p}" == "${_bp_port}" ]] && { _bp_proto="https"; break; }
        done
        _bp_url="${_bp_proto}://${_bp_ip}:${_bp_port}"
        _bp_ua="$(get_user_agent)"

        for _bp_word in "$@"; do
            _bp_host="${_bp_word}.${domain}"
            _bp_raw="$(curl "${_vhost_curl_opts[@]}" \
                -H "Host: ${_bp_host}" \
                -H "User-agent: ${_bp_ua}" \
                -o /dev/null -w "%{http_code} %{size_download}" \
                "${_bp_url}" 2>/dev/null)"
            _bp_status="${_bp_raw%% *}"
            _bp_len="${_bp_raw##* }"
            [[ -z "${_bp_len}" ]] && _bp_len=0
            _bp_diff=$(( _bp_len - _bp_baseline_len ))
            [[ "${_bp_diff}" -lt 0 ]] && _bp_diff=$(( -_bp_diff ))
            if [[ "${_bp_status}" != "${_bp_baseline_status}" || "${_bp_diff}" -gt 200 ]]; then
                echo "${_bp_host}" >> "${tmp_dir}/vhost_probe_worker_${_bp_ip}_${_bp_port}_$$.tmp"
            fi
        done
    }

    local _batch_size="${vhost_probe_batch_size:-50}"

    while IFS= read -r vhost_probe_ip; do
        [[ -z "${vhost_probe_ip}" ]] && continue
        vhost_probe_ip="$(echo "${vhost_probe_ip}" | grep -Eo "${IPv4_regex}")"
        [[ -z "${vhost_probe_ip}" ]] && continue

        local vhost_probe_rand_host
        vhost_probe_rand_host="$(tr -dc 'a-z' </dev/urandom | fold -w 12 | head -n1).${domain}"
        unset user_agent
        user_agent="$(get_user_agent)"

        local vhost_probe_port
        for vhost_probe_port in "${_vhost_ports[@]}"; do
            _vhost_port_alive "${vhost_probe_ip}" "${vhost_probe_port}" || continue
            local bp_proto="http"
            local p2
            for p2 in "${webapp_tls_ports[@]}"; do
                [[ "${p2}" == "${vhost_probe_port}" ]] && { bp_proto="https"; break; }
            done
            local bp_url="${bp_proto}://${vhost_probe_ip}:${vhost_probe_port}"
            local vhost_probe_baseline_raw
            vhost_probe_baseline_raw="$(curl "${_vhost_curl_opts[@]}" \
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
            local _batch=() _i=0
            for vhost_probe_word in "${vhost_probe_words[@]}"; do
                _batch+=("${vhost_probe_word}")
                ((_i += 1))
                if [[ "${_i}" -ge "${_batch_size}" ]]; then
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
                    _vhost_probe_batch_worker "${vhost_probe_ip}" "${vhost_probe_port}" \
                        "${vhost_probe_baseline_status}" "${vhost_probe_baseline_len}" "${_batch[@]}" &
                    vhost_probe_pids+=("$!")
                    _batch=()
                    _i=0
                fi
            done
            # Dispatch remaining words
            if [[ "${#_batch[@]}" -gt 0 ]]; then
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
                _vhost_probe_batch_worker "${vhost_probe_ip}" "${vhost_probe_port}" \
                    "${vhost_probe_baseline_status}" "${vhost_probe_baseline_len}" "${_batch[@]}" &
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
