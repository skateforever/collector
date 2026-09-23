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
# The baseline ("what does this IP:port answer for a vhost name that
# doesn't exist") is sampled vhost_baseline_samples times, each with its
# own random hostname — see vhost-check.sh's header for why a single
# sample isn't enough (a target whose default page varies per request
# would otherwise flag basically every candidate). A word only counts
# as a hit if it matches none of the baseline samples AND a repeat
# request to that same word reproduces the same reading — mirroring
# vhost_check_baseline()'s approach end to end, including the
# reproducibility re-check.
#
# A confirmed hit already carries everything vhost_check's STRONG tier
# carries (the IP and port it was probed on, plus the scheme) — there's
# no dual-tool consensus here (single curl, or ffuf), so there's no
# STRONG/WEAK split, just "confirmed" or nothing. vhost_probe_persist_hits()
# writes those hits to report_dir/vhost_probe_hits.txt and merges them
# into the SAME etc_hosts_file.txt / vhost_urls.txt vhost_check's STRONG
# hits use — a confirmed vhost_probe hit gets injected into /etc/hosts
# and scanned downstream exactly like a STRONG one, whether or not it
# also happens to have a public DNS record (most won't; that's the
# entire point of brute-forcing Host headers instead of just reading
# DNS). domains_recon.sh's dns_parallel_worker merge is a SEPARATE,
# additional enrichment for whichever hits DO also resolve publicly —
# it's not what makes a hit usable, it just adds independently-resolved
# IP data on top for the subset where that's available.
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

# Computes the ffuf-mode baseline for one target URL as a SET of
# vhost_baseline_samples independent samples (random hostname each).
# Prints one "size|hash" line per successful sample; returns 1 if every
# sample failed (the pair is dead).
vhost_probe_ffuf_baseline(){
    local url="$1"
    local samples="${vhost_baseline_samples:-3}"
    local i got_any="no" rand_host raw size hash
    for ((i = 0; i < samples; i++)); do
        rand_host="$(tr -dc 'a-z' </dev/urandom | fold -w 12 | head -n1).${domain}"
        raw="$(curl -k "${ffuf_curl_opts[@]}" \
            -H "Host: ${rand_host}" \
            -w $'\n%{size_download}' \
            "${url}" 2>/dev/null)"
        size="${raw##*$'\n'}"
        [[ -z "${size}" || "${size}" == "0" ]] && continue
        hash="$(printf '%s' "${raw%$'\n'*}" | md5sum | awk '{print $1}')"
        got_any="yes"
        printf '%s|%s\n' "${size}" "${hash}"
    done
    [[ "${got_any}" == "yes" ]] || return 1
}

# Re-verifies a single ffuf candidate against the full baseline sample
# set with a fresh curl request, and — if it still looks different —
# repeats that same request once more to confirm the reading is
# reproducible before reporting it. ffuf's own -fs only filters by exact
# size match, so this is what actually tells a genuine vhost apart from
# a same-size/different-content coincidence or from noise on a target
# whose default page varies per request.
# Args: $1=url $2=out_file $3=word $4=num_samples $5..=baseline samples
#       ("size|hash")
vhost_probe_ffuf_verify_worker(){
    local fvw_url="$1" fvw_out="$2" fvw_word="$3" fvw_num_samples="$4"
    shift 4
    local -a fvw_samples=()
    local i
    for ((i = 0; i < fvw_num_samples; i++)); do
        fvw_samples+=("$1")
        shift
    done

    _fvw_probe_once(){
        local raw size hash sample s_size s_hash diff
        raw="$(curl -k "${ffuf_curl_opts[@]}" \
            -H "Host: ${fvw_word}.${domain}" \
            -w $'\n%{size_download}' \
            "${fvw_url}" 2>/dev/null)"
        size="${raw##*$'\n'}"
        hash="$(printf '%s' "${raw%$'\n'*}" | md5sum | awk '{print $1}')"
        diff="yes"
        for sample in "${fvw_samples[@]}"; do
            IFS='|' read -r s_size s_hash <<< "${sample}"
            [[ "${size}" == "${s_size}" && "${hash}" == "${s_hash}" ]] && diff="no"
        done
        # A connection failure (no TCP response at all) is not evidence of
        # a distinct vhost — without this, two failed probes look
        # identical to each other and would otherwise pass the
        # reproducibility check below as a false "confirmed" hit.
        if [[ "${size}" == "0" || -z "${size}" ]] && [[ -z "${hash}" || "${hash}" == "d41d8cd98f00b204e9800998ecf8427e" ]]; then
            diff="no"
        fi
        printf '%s|%s|%s\n' "${size}" "${hash}" "${diff}"
    }

    local reading1 reading2 fvw_size fvw_hash fvw_diff
    reading1="$(_fvw_probe_once)"
    [[ "${reading1##*|}" == "yes" ]] || return 0

    reading2="$(_fvw_probe_once)"
    [[ "${reading2##*|}" == "yes" ]] || return 0
    [[ "${reading1%|*}" == "${reading2%|*}" ]] || return 0

    # url is "scheme://ip:port" (built as such, no path) — pull the pieces
    # back out so the hit line carries everything needed to act on it,
    # not just the bare hostname.
    local fvw_scheme="${fvw_url%%://*}"
    local fvw_ip="${fvw_url#*://}"; fvw_ip="${fvw_ip%%:*}"
    local fvw_port="${fvw_url##*:}"
    IFS='|' read -r fvw_size fvw_hash fvw_diff <<< "${reading1}"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "${fvw_ip}" "${fvw_port}" "${fvw_scheme}" "${fvw_word}.${domain}" "${fvw_size}" "${fvw_hash}" >> "${fvw_out}"
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
    local ffuf_ip ffuf_port ffuf_proto ffuf_url ffuf_out tls_p
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

            # Baseline: a SET of samples, not one. The hash is used later
            # to re-verify ffuf's hits (ffuf itself only filters by exact
            # size match via -fs, so it can't tell a genuinely different
            # vhost from a same-size/different-content coincidence).
            local -a ffuf_baseline_samples=()
            mapfile -t ffuf_baseline_samples < <(vhost_probe_ffuf_baseline "${ffuf_url}")

            # Skip port if every sample got no response
            [[ "${#ffuf_baseline_samples[@]}" -eq 0 ]] && continue

            # -fs takes a comma-separated list of sizes: filter out every
            # size observed across the baseline samples, not just one.
            local ffuf_fs_sizes
            ffuf_fs_sizes="$(printf '%s\n' "${ffuf_baseline_samples[@]}" | awk -F'|' '{print $1}' | sort -un | paste -sd, -)"

            ffuf_out="${tmp_dir}/ffuf_vhost_${ffuf_ip}_${ffuf_port}.tmp"

            # ffuf vhost mode: FUZZ is replaced with each wordlist entry
            # -fs filters out responses matching a baseline sample's size
            # -t threads, -timeout per-request timeout
            echo "ffuf -u ${ffuf_url} -H \"Host: FUZZ.${domain}\" -w ${ffuf_wordlist} -fs ${ffuf_fs_sizes} -t ${ffuf_threads_vp}" >> "${log_execution_file}"
            ffuf -u "${ffuf_url}" \
                -H "Host: FUZZ.${domain}" \
                -w "${ffuf_wordlist}" \
                -fs "${ffuf_fs_sizes}" \
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
                        vhost_probe_ffuf_verify_worker "${ffuf_url}" "${ffuf_verify_out}" "${ffuf_word}" \
                            "${#ffuf_baseline_samples[@]}" "${ffuf_baseline_samples[@]}" &
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
    vhost_probe_persist_hits
}

# Persists tmp_dir/vhost_probe_output.txt ("ip\tport\tscheme\thost\tsize\thash"
# lines, one per confirmed hit) to report_dir: a plain report file for manual
# review, laid out the SAME way as vhost_subdomains_strong/weak.txt
# ("scheme://host<TAB>ip:port<TAB>Size: N<TAB>Hash: X<TAB>tag") for a
# consistent look across all three vhost report files — the tag is always
# CONFIRMED here since there's no dual-tool consensus to split on (single
# curl, or ffuf), just confirmed-by-reproducibility or not in this file at
# all — plus a merge into the SAME etc_hosts_file.txt / vhost_urls.txt
# vhost_check's STRONG hits feed. A confirmed probe hit already cleared the
# same bar STRONG does (multi-sample baseline + reproducibility re-check),
# so it gets the same automatic /etc/hosts injection and
# webapp_consolidated.txt inclusion — see the file header for why that's
# the whole point (most real hits here won't have public DNS to fall back
# on). Appends + sort -u so this merges cleanly whether vhost_check already
# wrote to these files first or not.
vhost_probe_persist_hits(){
    [[ -s "${tmp_dir}/vhost_probe_output.txt" ]] || return 0

    awk -F'\t' '{
        ip=$1; port=$2; proto=$3; host=$4; size=$5; hash=$6;
        if ((proto=="http" && port=="80") || (proto=="https" && port=="443"))
            url=proto"://"host;
        else
            url=proto"://"host":"port;
        print url"\t"ip":"port"\tSize: "size"\tHash: "hash"\tCONFIRMED";
    }' "${tmp_dir}/vhost_probe_output.txt" | sort -u -o "${report_dir}/vhost_probe_hits.txt"

    awk -F'\t' 'BEGIN{OFS="\t"} {print $1, $4}' "${tmp_dir}/vhost_probe_output.txt" \
        >> "${report_dir}/etc_hosts_file.txt"
    sort -u -o "${report_dir}/etc_hosts_file.txt" "${report_dir}/etc_hosts_file.txt"

    awk -F'\t' '{
        port=$2; proto=$3; host=$4;
        if ((proto=="http" && port=="80") || (proto=="https" && port=="443"))
            print proto"://"host;
        else
            print proto"://"host":"port;
    }' "${tmp_dir}/vhost_probe_output.txt" >> "${report_dir}/vhost_urls.txt"
    sort -u -o "${report_dir}/vhost_urls.txt" "${report_dir}/vhost_urls.txt"
}

# Computes the bash-loop-mode baseline for one (IP, port) pair as a SET
# of vhost_baseline_samples independent samples (random hostname each).
# Prints one "status|size|hash" line per successful sample; returns 1 if
# every sample got no TCP response at all (the pair is dead).
# Args: $1=url $2..=curl options array
vhost_probe_baseline(){
    local url="$1"
    shift
    local -a curl_opts=("$@")
    local samples="${vhost_baseline_samples:-3}"
    local i got_any="no" rand_host ua raw trailer status len hash
    for ((i = 0; i < samples; i++)); do
        rand_host="$(tr -dc 'a-z' </dev/urandom | fold -w 12 | head -n1).${domain}"
        ua="$(get_user_agent)"
        raw="$(curl "${curl_opts[@]}" \
            -H "Host: ${rand_host}" \
            -H "User-agent: ${ua}" \
            -w $'\n%{http_code} %{size_download}' \
            "${url}" 2>/dev/null)"
        trailer="${raw##*$'\n'}"
        status="${trailer%% *}"
        len="${trailer##* }"
        [[ -z "${status}" || "${status}" == "000" ]] && continue
        [[ -z "${len}" ]] && len=0
        hash="$(printf '%s' "${raw%$'\n'*}" | md5sum | awk '{print $1}')"
        got_any="yes"
        printf '%s|%s|%s\n' "${status}" "${len}" "${hash}"
    done
    [[ "${got_any}" == "yes" ]] || return 1
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
    # Args: $1=IP $2=port $3=num_samples $4..$(3+num_samples)=baseline
    #       samples ("status|size|hash") remaining=words
    #
    # A word only counts as a hit if it matches NONE of the baseline
    # samples AND a repeat request to that same word reproduces the same
    # reading. Matching a sample means: status equal AND (size equal OR
    # hash equal) — same per-sample rule the old single-baseline check
    # used, just checked against every observed sample instead of one.
    vhost_probe_batch_worker(){
        local bp_ip="$1" bp_port="$2" bp_num_samples="$3"
        shift 3
        local -a bp_baseline_samples=()
        local i
        for ((i = 0; i < bp_num_samples; i++)); do
            bp_baseline_samples+=("$1")
            shift
        done
        local bp_proto="http" bp_url bp_word bp_host
        local tls_p

        for tls_p in "${webapp_tls_ports[@]}"; do
            [[ "${tls_p}" == "${bp_port}" ]] && { bp_proto="https"; break; }
        done
        bp_url="${bp_proto}://${bp_ip}:${bp_port}"

        _bp_probe_once(){
            local host="$1" ua raw trailer status len hash
            local sample s_status s_size s_hash diff
            ua="$(get_user_agent)"
            raw="$(curl "${vp_curl_opts[@]}" \
                -H "Host: ${host}" \
                -H "User-agent: ${ua}" \
                -w $'\n%{http_code} %{size_download}' \
                "${bp_url}" 2>/dev/null)"
            trailer="${raw##*$'\n'}"
            status="${trailer%% *}"
            len="${trailer##* }"
            [[ -z "${len}" ]] && len=0
            hash="$(printf '%s' "${raw%$'\n'*}" | md5sum | awk '{print $1}')"

            diff="yes"
            for sample in "${bp_baseline_samples[@]}"; do
                IFS='|' read -r s_status s_size s_hash <<< "${sample}"
                if [[ "${status}" == "${s_status}" ]] && { [[ "${len}" == "${s_size}" ]] || [[ "${hash}" == "${s_hash}" ]]; }; then
                    diff="no"
                fi
            done
            # A connection failure (no TCP response at all) is not evidence
            # of a distinct vhost — without this, two failed probes look
            # identical to each other and would otherwise pass the
            # reproducibility check below as a false "confirmed" hit.
            if [[ -z "${status}" || "${status}" == "000" ]]; then
                diff="no"
            fi
            printf '%s|%s|%s\n' "${len}" "${hash}" "${diff}"
        }

        local bp_reading1 bp_reading2 bp_len bp_hash bp_diff
        for bp_word in "$@"; do
            bp_host="${bp_word}.${domain}"

            bp_reading1="$(_bp_probe_once "${bp_host}")"
            [[ "${bp_reading1##*|}" == "yes" ]] || continue

            bp_reading2="$(_bp_probe_once "${bp_host}")"
            [[ "${bp_reading2##*|}" == "yes" ]] || continue
            [[ "${bp_reading1%|*}" == "${bp_reading2%|*}" ]] || continue

            IFS='|' read -r bp_len bp_hash bp_diff <<< "${bp_reading1}"
            printf '%s\t%s\t%s\t%s\t%s\t%s\n' "${bp_ip}" "${bp_port}" "${bp_proto}" "${bp_host}" "${bp_len}" "${bp_hash}" >> "${tmp_dir}/vhost_probe_worker_${bp_ip}_${bp_port}_$$.tmp"
        done
    }

    local batch_size="${vhost_probe_batch_size:-50}"

    while IFS= read -r vhost_probe_ip; do
        [[ -z "${vhost_probe_ip}" ]] && continue
        vhost_probe_ip="$(echo "${vhost_probe_ip}" | grep -Eo "${IPv4_regex}")"
        [[ -z "${vhost_probe_ip}" ]] && continue

        local vhost_probe_port
        for vhost_probe_port in "${vp_probe_ports[@]}"; do
            vhost_port_alive "${vhost_probe_ip}" "${vhost_probe_port}" || continue
            local bp_proto="http"
            local p2
            for p2 in "${webapp_tls_ports[@]}"; do
                [[ "${p2}" == "${vhost_probe_port}" ]] && { bp_proto="https"; break; }
            done
            local bp_url="${bp_proto}://${vhost_probe_ip}:${vhost_probe_port}"

            local -a vhost_probe_baseline_samples=()
            mapfile -t vhost_probe_baseline_samples < <(vhost_probe_baseline "${bp_url}" "${vp_curl_opts[@]}")

            # Early exit: if every sample got no response, skip this port.
            [[ "${#vhost_probe_baseline_samples[@]}" -eq 0 ]] && continue

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
                    vhost_probe_batch_worker "${vhost_probe_ip}" "${vhost_probe_port}" "${#vhost_probe_baseline_samples[@]}" \
                        "${vhost_probe_baseline_samples[@]}" "${batch[@]}" &
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
                vhost_probe_batch_worker "${vhost_probe_ip}" "${vhost_probe_port}" "${#vhost_probe_baseline_samples[@]}" \
                    "${vhost_probe_baseline_samples[@]}" "${batch[@]}" &
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
    vhost_probe_persist_hits
    echo "Done!"
}
