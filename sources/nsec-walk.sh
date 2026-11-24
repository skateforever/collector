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
    # Zone walking is inherently sequential (each step's query target
    # depends on the previous step's answer), so unlike asn-sweep.sh/
    # ptr-sweep.sh this isn't a parallelism candidate — but every dig
    # below used to run with dig's own multi-retry default timeout, and
    # up to nsec_max=2000 iterations of that (each one a fresh dig) is
    # still real time with nothing on stdout but "Executing..." until
    # the whole walk finishes or a nameserver stops answering. Capped
    # each lookup at 2s/1 try via dig_safe/dig_timeout instead, same as
    # every other dig call fixed this way elsewhere.
    echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing NSEC walk... "
    : > "${tmp_dir}/nsec_walk_output.tmp"
    nsec_ns="$(dig_safe NS "${domain}" | head -1 | sed 's/\.$//')"
    if [[ -z "${nsec_ns}" ]]; then
        # echo "Done!"
        return 0
    fi
    nsec_ns_ip="$(dig_safe A "${nsec_ns}" | grep -Eo "${IPv4_regex}" | head -1)"
    if [[ -z "${nsec_ns_ip}" ]]; then
        # echo "Done!"
        return 0
    fi
    # Detect NSEC vs NSEC3 — NSEC3 (hashed) cannot be walked
    nsec_check="$(dig_timeout +dnssec +short SOA "${domain}" "@${nsec_ns_ip}")"
    nsec_type_check="$(dig_timeout +dnssec NSEC3PARAM "${domain}" "@${nsec_ns_ip}" | grep -c 'NSEC3PARAM')"
    if [[ "${nsec_type_check}" -gt 0 ]]; then
        echo -e "\n${domain} uses NSEC3 — zone walking not possible" >> "${log_execution_file}"
        # echo "Done!"
        return 0
    fi
    echo -e "\nNSEC walk on ${domain} via ${nsec_ns} (${nsec_ns_ip})" >> "${log_execution_file}"
    nsec_current="${domain}"
    nsec_iterations=0
    nsec_max=2000
    while [[ "${nsec_iterations}" -lt "${nsec_max}" ]]; do
        nsec_iterations=$(( nsec_iterations + 1 ))
        echo -e "\ndig +dnssec NSEC \"${nsec_current}\" \"@${nsec_ns_ip}\"" >> "${log_execution_file}"
        nsec_answer="$(dig_timeout +dnssec NSEC "${nsec_current}" "@${nsec_ns_ip}")"
        nsec_owner="$(echo "${nsec_answer}" | awk '/NSEC/{print $1}' | sed 's/\.$//' | tr '[:upper:]' '[:lower:]' | head -1)"
        nsec_next="$(echo "${nsec_answer}" | awk '/NSEC/{print $5}' | sed 's/\.$//' | tr '[:upper:]' '[:lower:]' | head -1)"
        if [[ -n "${nsec_owner}" ]]; then
            echo "${nsec_owner}" | grep -Ei "(\.${domain}$|^${domain}$)" >> "${tmp_dir}/nsec_walk_output.tmp"
        fi
        if [[ -z "${nsec_next}" || "${nsec_next}" == "${domain}" || "${nsec_next}" == "${nsec_current}" ]]; then
            break
        fi
        nsec_current="${nsec_next}"
    done
    sort -u -o "${tmp_dir}/nsec_walk_output.tmp" "${tmp_dir}/nsec_walk_output.tmp" 2>/dev/null
    # echo "Done!"
}

nsec-walk-src
