#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * nsec-walk-src                                         #
#                                                           #
#############################################################

nsec-walk-src(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing NSEC walk... "
    : > "${tmp_dir}/nsec_walk_output.txt"
    nsec_ns="$(dig +short NS "${domain}" 2>/dev/null | head -1 | sed 's/\.$//')"
    if [[ -z "${nsec_ns}" ]]; then
        echo "Done!"
        return 0
    fi
    nsec_ns_ip="$(dig +short A "${nsec_ns}" 2>/dev/null | grep -Eo "${IPv4_regex}" | head -1)"
    if [[ -z "${nsec_ns_ip}" ]]; then
        echo "Done!"
        return 0
    fi
    # Detect NSEC vs NSEC3 — NSEC3 (hashed) cannot be walked
    nsec_check="$(dig +dnssec +short SOA "${domain}" "@${nsec_ns_ip}" 2>/dev/null)"
    nsec_type_check="$(dig +dnssec NSEC3PARAM "${domain}" "@${nsec_ns_ip}" 2>/dev/null | grep -c 'NSEC3PARAM')"
    if [[ "${nsec_type_check}" -gt 0 ]]; then
        echo -e "\n${domain} uses NSEC3 — zone walking not possible" >> "${log_execution_file}"
        echo "Done!"
        return 0
    fi
    echo -e "\nNSEC walk on ${domain} via ${nsec_ns} (${nsec_ns_ip})" >> "${log_execution_file}"
    nsec_current="${domain}"
    nsec_iterations=0
    nsec_max=2000
    while [[ "${nsec_iterations}" -lt "${nsec_max}" ]]; do
        nsec_iterations=$(( nsec_iterations + 1 ))
        echo -e "\ndig +dnssec NSEC \"${nsec_current}\" \"@${nsec_ns_ip}\"" >> "${log_execution_file}"
        nsec_answer="$(dig +dnssec NSEC "${nsec_current}" "@${nsec_ns_ip}" 2>/dev/null)"
        nsec_owner="$(echo "${nsec_answer}" | awk '/NSEC/{print $1}' | sed 's/\.$//' | tr '[:upper:]' '[:lower:]' | head -1)"
        nsec_next="$(echo "${nsec_answer}" | awk '/NSEC/{print $5}' | sed 's/\.$//' | tr '[:upper:]' '[:lower:]' | head -1)"
        if [[ -n "${nsec_owner}" ]]; then
            echo "${nsec_owner}" | grep -Ei "(\.${domain}$|^${domain}$)" >> "${tmp_dir}/nsec_walk_output.txt"
        fi
        if [[ -z "${nsec_next}" || "${nsec_next}" == "${domain}" || "${nsec_next}" == "${nsec_current}" ]]; then
            break
        fi
        nsec_current="${nsec_next}"
    done
    sort -u -o "${tmp_dir}/nsec_walk_output.txt" "${tmp_dir}/nsec_walk_output.txt" 2>/dev/null
    echo "Done!"
}

nsec-walk-src
