#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * ns-brute-src                                          #
#                                                           #
#############################################################

ns-brute-src(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing NS brute / zone transfer multi-vector... "
    : > "${tmp_dir}/ns_brute_output.txt"
    ns_brute_candidates=()
    ns_brute_seen_ips=()

    _ns_brute_add_candidate(){
        local ns_host="${1}"
        local ns_ip
        ns_host="$(echo "${ns_host}" | sed 's/\.$//')"
        [[ -z "${ns_host}" ]] && return
        ns_ip="$(dig +short A "${ns_host}" 2>/dev/null | grep -Eo "${IPv4_regex}" | head -1)"
        [[ -z "${ns_ip}" ]] && return
        if [[ ! " ${ns_brute_seen_ips[*]} " =~ " ${ns_ip} " ]]; then
            ns_brute_seen_ips+=("${ns_ip}")
            ns_brute_candidates+=("${ns_ip}|${ns_host}")
        fi
    }

    # Public NS records
    echo -e "\ndig +short NS \"${domain}\"" >> "${log_execution_file}"
    while IFS= read -r ns_brute_ns; do
        [[ -z "${ns_brute_ns}" ]] && continue
        _ns_brute_add_candidate "${ns_brute_ns}"
    done < <(dig +short NS "${domain}" 2>/dev/null)

    # SOA MNAME — the real primary, often differs from published NS
    echo -e "\ndig +short SOA \"${domain}\" (MNAME)" >> "${log_execution_file}"
    ns_brute_mname="$(dig +short SOA "${domain}" 2>/dev/null | awk '{print $1}')"
    [[ -n "${ns_brute_mname}" ]] && _ns_brute_add_candidate "${ns_brute_mname}"

    # Brute-force common NS naming patterns
    ns_brute_prefixes=(ns ns1 ns2 ns3 ns4 ns5 dns dns1 dns2 dns3 nameserver nameserver1 nameserver2 resolver auth hidden primary secondary slave)
    for ns_brute_prefix in "${ns_brute_prefixes[@]}"; do
        _ns_brute_add_candidate "${ns_brute_prefix}.${domain}"
    done

    if [[ ${#ns_brute_candidates[@]} -eq 0 ]]; then
        echo "Done!"
        return 0
    fi

    echo -e "\nNS brute candidates: ${ns_brute_candidates[*]}" >> "${log_execution_file}"

    # Detect SOA serial drift — lagging secondary may still allow AXFR
    ns_brute_serials=()
    for ns_brute_entry in "${ns_brute_candidates[@]}"; do
        ns_brute_ip="${ns_brute_entry%%|*}"
        ns_brute_host="${ns_brute_entry##*|}"
        ns_brute_serial="$(dig +short SOA "${domain}" "@${ns_brute_ip}" 2>/dev/null | awk '{print $3}')"
        [[ -n "${ns_brute_serial}" ]] && ns_brute_serials+=("${ns_brute_host}=${ns_brute_serial}")
    done
    [[ ${#ns_brute_serials[@]} -gt 1 ]] && echo -e "\nSOA serials: ${ns_brute_serials[*]}" >> "${log_execution_file}"

    # Try AXFR then IXFR on every candidate
    for ns_brute_entry in "${ns_brute_candidates[@]}"; do
        ns_brute_ip="${ns_brute_entry%%|*}"
        ns_brute_host="${ns_brute_entry##*|}"
        for ns_brute_xfr_type in AXFR IXFR; do
            echo -e "\ndig ${ns_brute_xfr_type} \"${domain}\" \"@${ns_brute_ip}\" (${ns_brute_host})" >> "${log_execution_file}"
            ns_brute_xfr="$(dig "${ns_brute_xfr_type}" "${domain}" "@${ns_brute_ip}" 2>/dev/null)"
            if echo "${ns_brute_xfr}" | grep -qvE "Transfer failed|servers could be reached|timed out|network unreachable|REFUSED|SERVFAIL"; then
                echo "${ns_brute_xfr}" >> "${tmp_dir}/ns_brute_output.txt"
                echo -e "\n${ns_brute_xfr_type} SUCCESS on ${ns_brute_host} (${ns_brute_ip})" >> "${log_execution_file}"
                break
            fi
        done
    done

    echo "Done!"
}

ns-brute-src
