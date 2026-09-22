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

# Computes the random-hostname baseline (curl + httpx) for one (IP, port)
# pair. Prints "curl_size curl_hash httpx_size httpx_hash" on stdout and
# returns 0 on success; returns 1 (nothing printed) if the pair gave no
# usable response at all, so the caller can skip it.
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
    local url="${proto}://${ip}:${port}"
    local baseline_host user_agent_baseline
    baseline_host="$(tr -dc 'a-z' </dev/urandom | fold -w 10 | head -n1).${domain}"
    user_agent_baseline="$(get_user_agent)"

    echo "curl ${vc_curl_opts[*]} -H \"User-Agent: ${user_agent_baseline}\" -H \"Host: ${baseline_host}\" \"${url}\"" >> "${log_execution_file}"
    local curl_baseline_raw curl_size curl_hash
    curl_baseline_raw="$(curl "${vc_curl_opts[@]}" -H "User-Agent: ${user_agent_baseline}" -H "Host: ${baseline_host}" -w $'\n%{size_download}' "${url}" 2>> "${log_execution_file}")"
    curl_hash="$(printf '%s' "${curl_baseline_raw%$'\n'*}" | md5sum | awk '{print $1}')"
    curl_size="${curl_baseline_raw##*$'\n'}"

    # Dead pair: no TCP response at all — nothing for the caller to work with.
    if [[ "${curl_size}" == "0" ]] && [[ -z "${curl_hash}" || "${curl_hash}" == "d41d8cd98f00b204e9800998ecf8427e" ]]; then
        return 1
    fi

    echo "echo \"${url}\" | httpx -silent -nc -timeout 10 -retries 0 -H \"Host: ${baseline_host}\" -H \"User-Agent: ${user_agent_baseline}\" -content-length -hash md5" >> "${log_execution_file}"
    local httpx_output httpx_size httpx_hash
    httpx_output="$(echo "${url}" | httpx -silent -nc -timeout 10 -retries 0 -H "Host: ${baseline_host}" -H "User-Agent: ${user_agent_baseline}" -content-length -hash md5 2>> "${log_execution_file}")"
    httpx_size="$(echo "${httpx_output}" | awk '{print $2}' | sed 's/\[// ; s/\]//')"
    httpx_hash="$(echo "${httpx_output}" | awk '{print $3}' | sed 's/\[// ; s/\]//')"

    printf '%s %s %s %s\n' "${curl_size}" "${curl_hash}" "${httpx_size}" "${httpx_hash}"
}

# Batch worker: probes a slice of candidate vhost names against one (IP,
# port) pair, comparing each against the baseline already computed for
# that pair (so the baseline itself is never re-fetched here).
# Args: $1=ip $2=port $3=curl_base_size $4=curl_base_hash
#       $5=httpx_base_size $6=httpx_base_hash $7=out_file $8..=vhost names
vhost_check_batch_worker(){
    local ip="$1" port="$2"
    local curl_base_size="$3" curl_base_hash="$4"
    local httpx_base_size="$5" httpx_base_hash="$6"
    local out_file="$7"
    shift 7

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
    local user_agent_vhost
    user_agent_vhost="$(get_user_agent)"

    # Dedupes identical (vhost, hash) hits within this batch — guards the
    # degenerate case of duplicate lines in the candidate file, since the
    # list is otherwise expected to already be sort -u'd upstream.
    local -A seen_responses
    local vhost curl_vhost_raw curl_vhost_size curl_vhost_hash
    local httpx_vhost_output httpx_vhost_size httpx_vhost_hash
    local curl_diff httpx_diff confidence combo_key

    for vhost in "$@"; do
        [[ -z "${vhost}" ]] && continue

        curl_vhost_raw="$(curl "${vc_curl_opts[@]}" -H "User-Agent: ${user_agent_vhost}" -H "Host: ${vhost}" -w $'\n%{size_download}' "${url}" 2>> "${log_execution_file}")"
        curl_vhost_hash="$(printf '%s' "${curl_vhost_raw%$'\n'*}" | md5sum | awk '{print $1}')"
        curl_vhost_size="${curl_vhost_raw##*$'\n'}"

        echo "echo \"${url}\" | httpx -silent -nc -timeout 10 -retries 0 -H \"Host: ${vhost}\" -H \"User-Agent: ${user_agent_vhost}\" -content-length -hash md5" >> "${log_execution_file}"
        httpx_vhost_output="$(echo "${url}" | httpx -silent -nc -timeout 10 -retries 0 -H "Host: ${vhost}" -H "User-Agent: ${user_agent_vhost}" -content-length -hash md5 2>> "${log_execution_file}")"
        httpx_vhost_size="$(echo "${httpx_vhost_output}" | awk '{print $2}' | sed 's/\[// ; s/\]//')"
        httpx_vhost_hash="$(echo "${httpx_vhost_output}" | awk '{print $3}' | sed 's/\[// ; s/\]//')"

        curl_diff="no"
        [[ "${curl_base_size}" != "${curl_vhost_size}" && "${curl_base_hash}" != "${curl_vhost_hash}" ]] && curl_diff="yes"

        httpx_diff="no"
        [[ "${httpx_base_size}" != "${httpx_vhost_size}" && "${httpx_base_hash}" != "${httpx_vhost_hash}" ]] && httpx_diff="yes"

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
    local -a vc_ports=()
    if [[ "${#vhost_port_detect[@]}" -gt 0 ]]; then
        vc_ports=("${vhost_port_detect[@]}")
    else
        vc_ports=("${webapp_port_detect[@]}")
    fi

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

                local baseline
                baseline="$(vhost_check_baseline "${IP}" "${port}")" || continue
                local curl_b_size curl_b_hash httpx_b_size httpx_b_hash
                read -r curl_b_size curl_b_hash httpx_b_size httpx_b_hash <<< "${baseline}"

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
                        vhost_check_batch_worker "${IP}" "${port}" \
                            "${curl_b_size}" "${curl_b_hash}" "${httpx_b_size}" "${httpx_b_hash}" \
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
                    vhost_check_batch_worker "${IP}" "${port}" \
                        "${curl_b_size}" "${curl_b_hash}" "${httpx_b_size}" "${httpx_b_hash}" \
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

        if [[ -s "${strong_out}" ]]; then
            tls_ports_pat="$(echo "${webapp_tls_ports[@]}" | tr ' ' '|')"
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
