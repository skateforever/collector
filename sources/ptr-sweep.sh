#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * ptr_sweep_worker                                      #
#   * ptr_sweep                                             #
#                                                           #
#############################################################
#
# PTR-sweeps the /24 block of every discovered infrastructure IP
# (infra_ipv4.txt) — not just the root domain's own IP. Call explicitly
# from domains_recon.sh after infra_data() populates infra_ipv4.txt:
#   ptr_sweep "${report_dir}/infra_ipv4.txt"
#
#############################################################

# ptr_sweep_worker — resolves one chunk of the full .0-.255 host-address
# list for a single /24 (one reverse lookup per address via dig_safe,
# which caps each failed lookup at 2s/1 try instead of dig's own
# multi-retry default — sequential WITHIN this worker; the parallelism
# comes from running ptr_sweep_threads of these at once, each on its own
# slice; see ptr_sweep below). Each worker writes to its own numbered
# temp file so concurrent workers never interleave writes to the same
# file.
ptr_sweep_worker(){
    local worker_id="$1"
    local chunk_file="$2"
    local ptr_base="$3"
    local out_file="$4"
    local last ptr_result
    while IFS= read -r last; do
        [[ -z "${last}" ]] && continue
        ptr_result="$(dig_safe PTR "${ptr_base}.${last}" | sed 's/\.$//' | tr '[:upper:]' '[:lower:]')"
        [[ -n "${ptr_result}" ]] && echo "${ptr_result}" >> "${out_file}_${worker_id}.tmp"
    done < "${chunk_file}"
}

ptr_sweep(){
    local ptr_ip_file="$1"
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing PTR sweep... "
    : > "${tmp_dir}/ptr_sweep_output.tmp"

    if [[ ! -s "${ptr_ip_file}" ]]; then
        echo "Done!"
        return 0
    fi

    # Every discovered IP can land in a different /24 — cap how many
    # distinct blocks we bother sweeping so a target with dozens of infra
    # IPs across many networks doesn't turn this into an excessively long
    # sweep (254 dig calls per block, now parallelized — see
    # ptr_sweep_threads in conf.d/functions.conf — but still real work).
    local ptr_max_blocks=10
    local -A ptr_seen_blocks
    local ptr_ip ptr_base ptr_last
    local ptr_checked=0 ptr_skipped=0
    local num_workers="${ptr_sweep_threads:-50}" worker_dir chunk_id pids pid i

    while IFS= read -r ptr_ip; do
        [[ -z "${ptr_ip}" ]] && continue
        ptr_base="$(echo "${ptr_ip}" | awk -F'.' '{print $1"."$2"."$3}')"

        # Dedupe: multiple discovered IPs often share the same /24 — only
        # sweep each block once regardless of how many IPs landed in it.
        if [[ -n "${ptr_seen_blocks[${ptr_base}]:-}" ]]; then
            continue
        fi

        if [[ "${ptr_checked}" -ge "${ptr_max_blocks}" ]]; then
            ((ptr_skipped += 1))
            continue
        fi
        ptr_seen_blocks[${ptr_base}]=1
        ((ptr_checked += 1))

        echo -e "\ndig: PTR sweep for /24 block of ${ptr_ip} (${ptr_base}.0/24), ${num_workers} workers" >> "${log_execution_file}"

        worker_dir="${tmp_dir}/ptr_sweep_$$_${ptr_base//./_}"
        mkdir -p "${worker_dir}"
        seq 1 254 > "${worker_dir}/all.tmp"
        # -d: numeric suffixes — see the same note on `split` in
        # dns_parallel_worker's caller (functions/domains_recon.sh).
        split -d -n l/"${num_workers}" "${worker_dir}/all.tmp" "${worker_dir}/chunk_"

        pids=()
        for ((i=0; i<num_workers; i++)); do
            printf -v chunk_id '%02d' "${i}"
            [[ -s "${worker_dir}/chunk_${chunk_id}" ]] || continue
            ptr_sweep_worker "${i}" "${worker_dir}/chunk_${chunk_id}" "${ptr_base}" "${tmp_dir}/ptr_sweep_output" &
            pids+=($!)
        done
        for pid in "${pids[@]}"; do
            wait "${pid}" 2>/dev/null
        done

        cat "${tmp_dir}/ptr_sweep_output"_*.tmp 2>/dev/null >> "${tmp_dir}/ptr_sweep_output.tmp"
        rm -rf "${worker_dir}" "${tmp_dir}/ptr_sweep_output"_*.tmp 2>/dev/null
    done < <(sort -u "${ptr_ip_file}")

    if [[ "${ptr_skipped}" -gt 0 ]]; then
        echo "ptr-sweep: skipped ${ptr_skipped} additional /24 block(s) beyond the ${ptr_max_blocks}-block cap" >> "${log_execution_file}"
    fi

    sort -u -o "${tmp_dir}/ptr_sweep_output.tmp" "${tmp_dir}/ptr_sweep_output.tmp" 2>/dev/null
    echo "Done!"
}
