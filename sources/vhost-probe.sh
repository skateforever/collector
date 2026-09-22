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
# should never resolve, mirroring vhost_check_baseline()'s approach.
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

# Re-verifies a single ffuf candidate with a fresh curl request, appending
# it to out_file only if size AND hash both differ from the baseline.
# ffuf's own -fs only confirms the size differs, so this catches the case
# where that size difference isn't matched by an actual content difference
# (or was a one-off blip) — same anti-noise rule vhost_check/vhost_probe's
# bash-loop worker use.
# Args: $1=url $2=baseline_size $3=baseline_hash $4=out_file $5=word
vhost_probe_ffuf_verify_worker(){
    local fvw_url="$1" fvw_baseline_size="$2" fvw_baseline_hash="$3" fvw_out="$4" fvw_word="$5"
    local fvw_raw fvw_size fvw_hash
    fvw_raw="$(curl -k "${ffuf_curl_opts[@]}" \
        -H "Host: ${fvw_word}.${domain}" \
        -w $'\n%{size_download}' \
        "${fvw_url}" 2>/dev/null)"
    fvw_size="${fvw_raw##*$'\n'}"
    fvw_hash="$(printf '%s' "${fvw_raw%$'\n'*}" | md5sum | awk '{print $1}')"
    if [[ "${fvw_size}" != "${fvw_baseline_size}" && "${fvw_hash}" != "${fvw_baseline_hash}" ]]; then
        echo "${fvw_word}.${domain}" >> "${fvw_out}"
    fi
}

# Fast vhost probe using ffuf's native vhost mode.
# Replaces the bash curl loop with a single ffuf invocation per (IP, port).
# Requires: ffuf in PATH, vhost_use_ffuf=yes in conf.d/functions.conf.
vhost_probe_ffuf(){
    local ffuf_ip_file="$1"
    local ffuf_threads_vp="${vhost_ffuf_threads:-50}"
    local ffuf_wordlist="${collector_vhost_probe_words}"

    if [[ ! -s "${ffuf_wordlist}" ]]; then
        echo "Fail! (wordlist missing: ${ffuf_wordlist})"
        return 0
    fi

    : > "${tmp_dir}/vhost_probe_output.txt"
    local ffuf_ip ffuf_port ffuf_proto ffuf_url
    local ffuf_baseline_raw ffuf_baseline_size ffuf_baseline_hash ffuf_rand_host ffuf_out tls_p
    local -a ffuf_curl_opts=()
    if [[ "${#vhost_curl_options[@]}" -gt 0 ]]; then
        ffuf_curl_opts=("${vhost_curl_options[@]}")
    else
        ffuf_curl_opts=("${curl_options_fast[@]}")
    fi

    while IFS= read -r ffuf_ip; do
        [[ -z "${ffuf_ip}" ]] && continue
        ffuf_ip="$(echo "${ffuf_ip}" | grep -Eo "${IPv4_regex}")"
        [[ -z "${ffuf_ip}" ]] && continue

        # No vhost-specific port list — always the same ports webapp-detection
        # picked for this run (-wsd/-wcp/-wld).
        local -a vp_ports=("${webapp_port_detect[@]}")

        for ffuf_port in "${vp_ports[@]}"; do
            ffuf_proto="http"
            for tls_p in "${webapp_tls_ports[@]}"; do
                [[ "${tls_p}" == "${ffuf_port}" ]] && { ffuf_proto="https"; break; }
            done
            ffuf_url="${ffuf_proto}://${ffuf_ip}:${ffuf_port}"

            # Get baseline response (size + hash) with a random hostname.
            # The hash is used later to re-verify ffuf's hits (ffuf itself
            # only filters by exact size match via -fs, so it can't tell a
            # genuinely different vhost from a same-size/different-content
            # coincidence).
            ffuf_rand_host="$(tr -dc 'a-z' </dev/urandom | fold -w 12 | head -n1).${domain}"
            ffuf_baseline_raw="$(curl -k "${ffuf_curl_opts[@]}" \
                -H "Host: ${ffuf_rand_host}" \
                -w $'\n%{size_download}' \
                "${ffuf_url}" 2>/dev/null)"
            ffuf_baseline_size="${ffuf_baseline_raw##*$'\n'}"
            ffuf_baseline_hash="$(printf '%s' "${ffuf_baseline_raw%$'\n'*}" | md5sum | awk '{print $1}')"

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

            # Parse ffuf CSV output: column 1 (FUZZ) is the matched word —
            # header is "FUZZ,url,redirectlocation,position,status_code,
            # content_length,content_words,content_lines,content_type,
            # duration,resultfile,Ffufhash".
            if [[ -s "${ffuf_out}" ]]; then
                local -a ffuf_candidates=()
                local ffuf_word ffuf_rest
                while IFS=',' read -r ffuf_word ffuf_rest; do
                    [[ -n "${ffuf_word}" ]] && ffuf_candidates+=("${ffuf_word}")
                done < <(tail -n+2 "${ffuf_out}")

                if [[ "${#ffuf_candidates[@]}" -gt 0 ]]; then
                    # One background worker per candidate, capped at
                    # ffuf_threads_vp concurrent — same concurrency budget
                    # ffuf itself used for the fuzzing pass. On a noisy
                    # target (-fs alone lets most of the wordlist through
                    # as "candidates"), this is what keeps verification
                    # from turning into a multi-minute serial curl loop.
                    local ffuf_verify_out="${tmp_dir}/ffuf_verify_${ffuf_ip}_${ffuf_port}_$$.tmp"
                    : > "${ffuf_verify_out}"
                    local -a ffuf_verify_pids=() ffuf_verify_alive=()
                    local ffuf_verify_pid
                    for ffuf_word in "${ffuf_candidates[@]}"; do
                        while :; do
                            ffuf_verify_alive=()
                            for ffuf_verify_pid in "${ffuf_verify_pids[@]}"; do
                                kill -0 "${ffuf_verify_pid}" 2>/dev/null && ffuf_verify_alive+=("${ffuf_verify_pid}")
                            done
                            ffuf_verify_pids=("${ffuf_verify_alive[@]}")
                            [[ "${#ffuf_verify_pids[@]}" -lt "${ffuf_threads_vp}" ]] && break
                            sleep 0.2
                        done
                        vhost_probe_ffuf_verify_worker "${ffuf_url}" "${ffuf_baseline_size}" "${ffuf_baseline_hash}" \
                            "${ffuf_verify_out}" "${ffuf_word}" &
                        ffuf_verify_pids+=("$!")
                    done
                    for ffuf_verify_pid in "${ffuf_verify_pids[@]}"; do
                        wait "${ffuf_verify_pid}" 2>/dev/null
                    done
                    cat "${ffuf_verify_out}" >> "${tmp_dir}/vhost_probe_output.txt" 2>/dev/null
                    rm -f "${ffuf_verify_out}"
                fi
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
    # conf.d/operation.conf, default: support/runtime/wordlists/vhost-probe-names.txt).
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
    # No vhost-specific port list — always the same ports webapp-detection
    # picked for this run (-wsd/-wcp/-wld).
    local -a vp_probe_ports=("${webapp_port_detect[@]}")
    local vhost_probe_pids=()
    local vhost_probe_pid vhost_probe_alive_pids=()
    local -a vp_curl_opts=()
    if [[ "${#vhost_curl_options[@]}" -gt 0 ]]; then
        vp_curl_opts=("${vhost_curl_options[@]}")
    else
        vp_curl_opts=("${curl_options_fast[@]}")
    fi

    # Batch worker: probes a slice of the wordlist for a single (IP, port) pair.
    # Args: $1=IP $2=port $3=baseline_status $4=baseline_len $5=baseline_hash $6..=words
    #
    # A hit needs the status to differ, OR size AND hash to *both* differ.
    # Requiring both size and hash (instead of just checking the hash) is
    # what keeps pages with per-request dynamic content (CSRF token,
    # timestamp, request id) from flagging as a false positive on every
    # single word — that kind of noise usually leaves size unchanged while
    # still flipping the hash. Same rule vhost_check uses for its own
    # curl_diff/httpx_diff (sources/vhost-check.sh).
    vhost_probe_batch_worker(){
        local bp_ip="$1" bp_port="$2" bp_baseline_status="$3" bp_baseline_len="$4" bp_baseline_hash="$5"
        shift 5
        local bp_proto="http" bp_url bp_ua bp_word bp_host
        local bp_raw bp_trailer bp_status bp_len bp_hash
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
                -w $'\n%{http_code} %{size_download}' \
                "${bp_url}" 2>/dev/null)"
            bp_trailer="${bp_raw##*$'\n'}"
            bp_status="${bp_trailer%% *}"
            bp_len="${bp_trailer##* }"
            [[ -z "${bp_len}" ]] && bp_len=0
            bp_hash="$(printf '%s' "${bp_raw%$'\n'*}" | md5sum | awk '{print $1}')"
            if [[ "${bp_status}" != "${bp_baseline_status}" ]] || \
               { [[ "${bp_len}" != "${bp_baseline_len}" ]] && [[ "${bp_hash}" != "${bp_baseline_hash}" ]]; }; then
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
            local vhost_probe_baseline_raw vhost_probe_baseline_trailer
            vhost_probe_baseline_raw="$(curl "${vp_curl_opts[@]}" \
                -H "Host: ${vhost_probe_rand_host}" \
                -H "User-agent: ${user_agent}" \
                -w $'\n%{http_code} %{size_download}' \
                "${bp_url}" 2>/dev/null)"
            local vhost_probe_baseline_status vhost_probe_baseline_len vhost_probe_baseline_hash
            vhost_probe_baseline_trailer="${vhost_probe_baseline_raw##*$'\n'}"
            vhost_probe_baseline_status="${vhost_probe_baseline_trailer%% *}"
            vhost_probe_baseline_len="${vhost_probe_baseline_trailer##* }"
            [[ -z "${vhost_probe_baseline_len}" ]] && vhost_probe_baseline_len=0
            vhost_probe_baseline_hash="$(printf '%s' "${vhost_probe_baseline_raw%$'\n'*}" | md5sum | awk '{print $1}')"

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
                        "${vhost_probe_baseline_status}" "${vhost_probe_baseline_len}" "${vhost_probe_baseline_hash}" "${batch[@]}" &
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
                    "${vhost_probe_baseline_status}" "${vhost_probe_baseline_len}" "${vhost_probe_baseline_hash}" "${batch[@]}" &
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
