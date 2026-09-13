#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
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

ptr_sweep(){
    local ptr_ip_file="$1"
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing PTR sweep... "
    : > "${tmp_dir}/ptr_sweep_output.txt"

    if [[ ! -s "${ptr_ip_file}" ]]; then
        echo "Done!"
        return 0
    fi

    # Every discovered IP can land in a different /24 — cap how many
    # distinct blocks we bother sweeping so a target with dozens of infra
    # IPs across many networks doesn't turn this into a multi-hour sweep
    # (254 dig calls per block).
    local ptr_max_blocks=10
    local -A ptr_seen_blocks
    local ptr_ip ptr_base ptr_result ptr_last
    local ptr_checked=0 ptr_skipped=0

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

        echo -e "\ndig: PTR sweep for /24 block of ${ptr_ip} (${ptr_base}.0/24)" >> "${log_execution_file}"
        for ptr_last in $(seq 1 254); do
            ptr_result="$(dig +short -x "${ptr_base}.${ptr_last}" 2>/dev/null | sed 's/\.$//' | tr '[:upper:]' '[:lower:]')"
            if [[ -n "${ptr_result}" ]]; then
                echo "${ptr_result}" >> "${tmp_dir}/ptr_sweep_output.txt"
            fi
        done
    done < <(sort -u "${ptr_ip_file}")

    if [[ "${ptr_skipped}" -gt 0 ]]; then
        echo "ptr-sweep: skipped ${ptr_skipped} additional /24 block(s) beyond the ${ptr_max_blocks}-block cap" >> "${log_execution_file}"
    fi

    sort -u -o "${tmp_dir}/ptr_sweep_output.txt" "${tmp_dir}/ptr_sweep_output.txt" 2>/dev/null
    echo "Done!"
}
