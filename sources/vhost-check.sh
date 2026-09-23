#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * vhost_check_baseline                                  #
#   * vhost_check_batch_worker                              #
#   * vhost_check                                           #
#                                                           #
#############################################################
#
# Probes unresolved subdomains (domains_without_resolution.txt)
# against live target IPs (infra_ipv4.txt) using curl + httpx
# with a random-hostname baseline for false-positive suppression.
#
# The candidate name list is split into batches and each batch runs as
# its own background worker (same fan-out pattern as vhost_probe),
# instead of a single sequential curl+httpx loop per (IP, port) pair.
# The baseline (curl+httpx against a random hostname) is computed once
# per pair and handed to every batch worker for that pair, so it isn't
# repeated per name.
#
# The baseline is sampled vhost_baseline_samples times (each with its
# own random hostname), not just once. A single sample can't tell a
# genuinely static "no such vhost" response from one draw of a page
# that varies per request (CSRF token, timestamp, request id, A/B
# content) — comparing every candidate against just that one snapshot
# then flags basically everything as "different" on a target like
# that. Comparing against the whole set of observed baseline samples
# instead tolerates that bounded variance without losing sensitivity
# to a real, distinct vhost. Candidates that still look different are
# re-probed once more before being reported (see vhost_check_batch_worker)
# — a genuine vhost reproduces; noise usually doesn't.
#
# Call explicitly from domains_recon.sh after infra_data():
#   [[ -s "…/domains_without_resolution.txt" ]] && \
#   [[ -s "…/infra_ipv4.txt" ]] && \
#       vhost_check "…/domains_without_resolution.txt" "…/infra_ipv4.txt"
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

# One curl+httpx probe against a fresh random hostname. Prints
# "curl_size|curl_hash|httpx_size|httpx_hash" on success; prints nothing
# and returns 1 if the pair gave no TCP response at all for this sample.
vhost_check_baseline_sample(){
    local ip="$1" port="$2" proto="$3"
    local -a vc_curl_opts=("${@:4}")
    local url="${proto}://${ip}:${port}"
    local baseline_host user_agent_baseline
    baseline_host="$(tr -dc 'a-z' </dev/urandom | fold -w 10 | head -n1).${domain}"
    user_agent_baseline="$(get_user_agent)"

    echo "curl ${vc_curl_opts[*]} -H \"User-Agent: ${user_agent_baseline}\" -H \"Host: ${baseline_host}\" \"${url}\"" >> "${log_execution_file}"
    local curl_baseline_raw curl_size curl_hash
    curl_baseline_raw="$(curl "${vc_curl_opts[@]}" -H "User-Agent: ${user_agent_baseline}" -H "Host: ${baseline_host}" -w $'\n%{size_download}' "${url}" 2>> "${log_execution_file}")"
    curl_hash="$(printf '%s' "${curl_baseline_raw%$'\n'*}" | md5sum | awk '{print $1}')"
    curl_size="${curl_baseline_raw##*$'\n'}"

    # No TCP response at all for this sample — nothing to report.
    if [[ "${curl_size}" == "0" ]] && [[ -z "${curl_hash}" || "${curl_hash}" == "d41d8cd98f00b204e9800998ecf8427e" ]]; then
        return 1
    fi

    echo "echo \"${url}\" | httpx -silent -nc -timeout 10 -retries 0 -H \"Host: ${baseline_host}\" -H \"User-Agent: ${user_agent_baseline}\" -content-length -hash md5" >> "${log_execution_file}"
    local httpx_output httpx_size httpx_hash
    httpx_output="$(echo "${url}" | httpx -silent -nc -timeout 10 -retries 0 -H "Host: ${baseline_host}" -H "User-Agent: ${user_agent_baseline}" -content-length -hash md5 2>> "${log_execution_file}")"
    httpx_size="$(echo "${httpx_output}" | awk '{print $2}' | sed 's/\[// ; s/\]//')"
    httpx_hash="$(echo "${httpx_output}" | awk '{print $3}' | sed 's/\[// ; s/\]//')"

    printf '%s|%s|%s|%s\n' "${curl_size}" "${curl_hash}" "${httpx_size}" "${httpx_hash}"
}

# Computes the random-hostname baseline for one (IP, port) pair as a SET
# of vhost_baseline_samples independent samples (see the file header for
# why one sample isn't enough). Prints one "curl_size|curl_hash|httpx_size|
# httpx_hash" line per successful sample; returns 1 if every sample failed
# (the pair is dead), so the caller can skip it.
vhost_check_baseline(){
    local ip="$1" port="$2"
    local proto="http" p
    local -a vc_curl_opts=()
    if [[ "${#vhost_curl_options[@]}" -gt 0 ]]; then
        vc_curl_opts=("${vhost_curl_options[@]}")
    else
        vc_curl_opts=("${curl_options_fast[@]}")
    fi
    for p in "${webapp_tls_ports[@]}"; do
        [[ "${p}" == "${port}" ]] && { proto="https"; break; }
    done

    local samples="${vhost_baseline_samples:-3}"
    local i got_any="no" sample
    for ((i = 0; i < samples; i++)); do
        sample="$(vhost_check_baseline_sample "${ip}" "${port}" "${proto}" "${vc_curl_opts[@]}")" || continue
        got_any="yes"
        printf '%s\n' "${sample}"
    done
    [[ "${got_any}" == "yes" ]] || return 1
}

# Batch worker: probes a slice of candidate vhost names against one (IP,
# port) pair, comparing each against the baseline sample set already
# computed for that pair (so the baseline itself is never re-fetched here).
# Args: $1=ip $2=port $3=num_samples $4..$(3+num_samples)=baseline samples
#       ("curl_size|curl_hash|httpx_size|httpx_hash") $next=out_file
#       remaining=vhost names
vhost_check_batch_worker(){
    local ip="$1" port="$2" num_samples="$3"
    shift 3
    local -a baseline_samples=()
    local i
    for ((i = 0; i < num_samples; i++)); do
        baseline_samples+=("$1")
        shift
    done
    local out_file="$1"
    shift

    local proto="http" p
    local -a vc_curl_opts=()
    if [[ "${#vhost_curl_options[@]}" -gt 0 ]]; then
        vc_curl_opts=("${vhost_curl_options[@]}")
    else
        vc_curl_opts=("${curl_options_fast[@]}")
    fi
    for p in "${webapp_tls_ports[@]}"; do
        [[ "${p}" == "${port}" ]] && { proto="https"; break; }
    done
    local url="${proto}://${ip}:${port}"

    # Dedupes identical (vhost, hash) hits within this batch — guards the
    # degenerate case of duplicate lines in the candidate file, since the
    # list is otherwise expected to already be sort -u'd upstream.
    local -A seen_responses

    # Probes $1=vhost once with curl+httpx. Echoes
    # "curl_size|curl_hash|httpx_size|httpx_hash|confidence" — confidence
    # is STRONG/WEAK/"" (empty means "matches the baseline set, not a hit").
    _vc_probe_once(){
        local vhost="$1" ua curl_raw curl_hash curl_size
        local httpx_output httpx_size httpx_hash
        local sample s_curl_size s_curl_hash s_httpx_size s_httpx_hash
        local curl_diff httpx_diff confidence

        ua="$(get_user_agent)"
        curl_raw="$(curl "${vc_curl_opts[@]}" -H "User-Agent: ${ua}" -H "Host: ${vhost}" -w $'\n%{size_download}' "${url}" 2>> "${log_execution_file}")"
        curl_hash="$(printf '%s' "${curl_raw%$'\n'*}" | md5sum | awk '{print $1}')"
        curl_size="${curl_raw##*$'\n'}"

        echo "echo \"${url}\" | httpx -silent -nc -timeout 10 -retries 0 -H \"Host: ${vhost}\" -H \"User-Agent: ${ua}\" -content-length -hash md5" >> "${log_execution_file}"
        httpx_output="$(echo "${url}" | httpx -silent -nc -timeout 10 -retries 0 -H "Host: ${vhost}" -H "User-Agent: ${ua}" -content-length -hash md5 2>> "${log_execution_file}")"
        httpx_size="$(echo "${httpx_output}" | awk '{print $2}' | sed 's/\[// ; s/\]//')"
        httpx_hash="$(echo "${httpx_output}" | awk '{print $3}' | sed 's/\[// ; s/\]//')"

        # "no diff" as soon as this reading matches ANY observed baseline
        # sample — not just a single frozen one.
        curl_diff="yes"
        httpx_diff="yes"
        for sample in "${baseline_samples[@]}"; do
            IFS='|' read -r s_curl_size s_curl_hash s_httpx_size s_httpx_hash <<< "${sample}"
            [[ "${curl_size}" == "${s_curl_size}" && "${curl_hash}" == "${s_curl_hash}" ]] && curl_diff="no"
            [[ "${httpx_size}" == "${s_httpx_size}" && "${httpx_hash}" == "${s_httpx_hash}" ]] && httpx_diff="no"
        done

        # A connection failure (no TCP response, or httpx got nothing) is
        # not evidence of a distinct vhost — without this, two failed
        # probes look identical to each other and would otherwise pass
        # the reproducibility check below as a false "confirmed" hit.
        if [[ "${curl_size}" == "0" || -z "${curl_size}" ]] && [[ -z "${curl_hash}" || "${curl_hash}" == "d41d8cd98f00b204e9800998ecf8427e" ]]; then
            curl_diff="no"
        fi
        if [[ "${httpx_size}" == "0" || -z "${httpx_size}" ]] && [[ -z "${httpx_hash}" || "${httpx_hash}" == "d41d8cd98f00b204e9800998ecf8427e" ]]; then
            httpx_diff="no"
        fi

        confidence=""
        if [[ "${curl_diff}" == "yes" && "${httpx_diff}" == "yes" ]]; then
            confidence="STRONG"
        elif [[ "${curl_diff}" == "yes" || "${httpx_diff}" == "yes" ]]; then
            confidence="WEAK"
        fi

        printf '%s|%s|%s|%s|%s\n' "${curl_size}" "${curl_hash}" "${httpx_size}" "${httpx_hash}" "${confidence}"
    }

    local vhost reading1 reading2 confidence1 confidence2 combo_key
    local r_curl_size r_curl_hash r_httpx_size r_httpx_hash
    for vhost in "$@"; do
        [[ -z "${vhost}" ]] && continue

        reading1="$(_vc_probe_once "${vhost}")"
        confidence1="${reading1##*|}"
        [[ -z "${confidence1}" ]] && continue

        # Looks different from the baseline set — confirm it's reproducible
        # before trusting it. A real distinct vhost gives the same answer
        # twice; noise (dynamic content unrelated to the Host header)
        # usually doesn't.
        reading2="$(_vc_probe_once "${vhost}")"
        confidence2="${reading2##*|}"
        [[ -z "${confidence2}" ]] && continue
        [[ "${reading1%|*}" == "${reading2%|*}" ]] || continue

        IFS='|' read -r r_curl_size r_curl_hash r_httpx_size r_httpx_hash confidence1 <<< "${reading1}"
        combo_key="${vhost}_${r_httpx_hash}"
        if [[ -z "${seen_responses[$combo_key]}" ]]; then
            printf '%s\t%s\tSize: %s\tHash: %s\t%s\n' "${vhost}" "${ip}:${port}" "${r_httpx_size}" "${r_httpx_hash}" "${confidence1}" >> "${out_file}"
            seen_responses[$combo_key]=1
        fi
    done
}

vhost_check(){
    local vhost_name_file="$1"
    local vhost_ip_file="$2"
    local max_workers="${vhost_check_processes:-16}"
    local batch_size="${vhost_check_batch_size:-20}"
    local strong_out="${tmp_dir}/vhost_subdomains_strong.tmp"
    local weak_out="${tmp_dir}/vhost_subdomains_weak.tmp"
    local IP port
    local -a worker_pids=()
    local pid alive
    # No vhost-specific port list — always the same ports webapp-detection
    # picked for this run (-wsd/-wcp/-wld).
    local -a vc_ports=("${webapp_port_detect[@]}")

    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Looking for vhost with dead subdomains... "
    echo -e "\n" >> "${log_execution_file}"

    if [[ -s "${vhost_ip_file}" ]]; then
        : > "${strong_out}"
        : > "${weak_out}"
        rm -f "${tmp_dir}"/vhost_check_batch_*.tmp 2>/dev/null

        local -a vhost_names=()
        mapfile -t vhost_names < <(grep -Ev '^[[:space:]]*$' "${vhost_name_file}")

        while IFS= read -r IP; do
            [[ -z "${IP}" ]] && continue
            for port in "${vc_ports[@]}"; do
                # Skip ports that don't respond to TCP at all.
                vhost_port_alive "${IP}" "${port}" || continue

                local -a baseline_samples=()
                mapfile -t baseline_samples < <(vhost_check_baseline "${IP}" "${port}")
                [[ "${#baseline_samples[@]}" -eq 0 ]] && continue

                # Chop the candidate list into batches, one background
                # worker per batch, capped at max_workers concurrent —
                # same fan-out pattern vhost_probe uses for its wordlist.
                local batch=() bidx=0 wname
                for wname in "${vhost_names[@]}"; do
                    batch+=("${wname}")
                    ((bidx += 1))
                    if [[ "${bidx}" -ge "${batch_size}" ]]; then
                        while :; do
                            alive=()
                            for pid in "${worker_pids[@]}"; do
                                kill -0 "${pid}" 2>/dev/null && alive+=("${pid}")
                            done
                            worker_pids=("${alive[@]}")
                            [[ "${#worker_pids[@]}" -lt "${max_workers}" ]] && break
                            sleep 0.3
                        done
                        vhost_check_batch_worker "${IP}" "${port}" "${#baseline_samples[@]}" \
                            "${baseline_samples[@]}" \
                            "${tmp_dir}/vhost_check_batch_${IP}_${port}_$$_${RANDOM}.tmp" \
                            "${batch[@]}" &
                        worker_pids+=("$!")
                        batch=()
                        bidx=0
                    fi
                done
                # Dispatch the remaining (partial) batch, if any.
                if [[ "${#batch[@]}" -gt 0 ]]; then
                    while :; do
                        alive=()
                        for pid in "${worker_pids[@]}"; do
                            kill -0 "${pid}" 2>/dev/null && alive+=("${pid}")
                        done
                        worker_pids=("${alive[@]}")
                        [[ "${#worker_pids[@]}" -lt "${max_workers}" ]] && break
                        sleep 0.3
                    done
                    vhost_check_batch_worker "${IP}" "${port}" "${#baseline_samples[@]}" \
                        "${baseline_samples[@]}" \
                        "${tmp_dir}/vhost_check_batch_${IP}_${port}_$$_${RANDOM}.tmp" \
                        "${batch[@]}" &
                    worker_pids+=("$!")
                fi
            done
        done < "${vhost_ip_file}"

        for pid in "${worker_pids[@]}"; do
            wait "${pid}" 2>/dev/null
        done

        # Aggregate per-batch outputs into strong/weak buckets.
        local line conf per_batch_out
        for per_batch_out in "${tmp_dir}"/vhost_check_batch_*_$$_*.tmp; do
            [[ -s "${per_batch_out}" ]] || continue
            while IFS= read -r line; do
                conf="${line##*$'\t'}"
                if [[ "${conf}" == "STRONG" ]]; then
                    echo "${line}" >> "${strong_out}"
                else
                    echo "${line}" >> "${weak_out}"
                fi
            done < "${per_batch_out}"
            rm -f "${per_batch_out}"
        done

        # Persist both tiers to report_dir, regardless of confidence. STRONG
        # still drives etc_hosts_file.txt/vhost_urls.txt below (only STRONG
        # gets auto-injected into /etc/hosts and auto-scanned downstream —
        # that's a deliberate confidence gate, not a bug). WEAK never got a
        # report artifact before this; it was computed, then discarded with
        # nothing else in the codebase ever reading it. It stays out of the
        # automated pipeline (still not confident enough to script /etc/hosts
        # against, or hand to nuclei/gobuster unsupervised) but a
        # human can now actually see and manually verify these candidates
        # instead of them vanishing silently.
        local tls_ports_pat
        tls_ports_pat="$(echo "${webapp_tls_ports[@]}" | tr ' ' '|')"

        # Field 1 gets a scheme:// prefix only in the report_dir copies, for
        # human readability. The .tmp files below stay hostname-only — that's
        # the format domains_recon.sh's vhost_subdomains_strong.tmp reader
        # expects (bare $1 for domain matching / etc_hosts_file.txt lookup).
        awk -v tls="${tls_ports_pat}" 'BEGIN{OFS="\t"}{split($2,a,":");port=a[2];proto=(port~"^("tls")$")?"https":"http";$1=proto"://"$1;print}' "${strong_out}" 2>/dev/null | sort -u -o "${report_dir}/vhost_subdomains_strong.txt"
        awk -v tls="${tls_ports_pat}" 'BEGIN{OFS="\t"}{split($2,a,":");port=a[2];proto=(port~"^("tls")$")?"https":"http";$1=proto"://"$1;print}' "${weak_out}" 2>/dev/null | sort -u -o "${report_dir}/vhost_subdomains_weak.txt"

        if [[ -s "${strong_out}" ]]; then
            awk 'BEGIN{OFS="\t"}{split($2,a,":"); print a[1], $1}' "${strong_out}" | sort -u > "${tmp_dir}/etc_hosts_file.tmp"
            sort -u -o "${report_dir}/etc_hosts_file.txt" "${tmp_dir}/etc_hosts_file.tmp"
            awk -v tls="${tls_ports_pat}" '{split($2,a,":");port=a[2];proto=(port~"^("tls")$")?"https":"http";if((proto=="http"&&port=="80")||(proto=="https"&&port=="443"))print proto"://"$1;else print proto"://"$1":"port}' "${strong_out}" | sort -u > "${tmp_dir}/vhost_urls.tmp"
            sort -u -o "${report_dir}/vhost_urls.txt" "${tmp_dir}/vhost_urls.tmp"
            [ -s "${report_dir}/domains_without_resolution.txt" ] && awk '{print $1}' "${strong_out}" | sort -u | while IFS= read -r vhost; do sed -i "/^${vhost}$/d" "${report_dir}/domains_without_resolution.txt"; done
        fi
        # build_consolidated_urls is intentionally NOT called here.
        # It will be called once by domains_recon.sh after vhost_probe also
        # finishes, so that both vhost_check and vhost_probe hits are included
        # in the consolidated URL list in a single pass.
        echo "Done!"
    else
        echo "Fail!"
    fi
}
