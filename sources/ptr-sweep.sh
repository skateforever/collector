#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * ptr-sweep-src                                         #
#                                                           #
#############################################################

ptr-sweep-src(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing PTR sweep... "
    : > "${tmp_dir}/ptr_sweep_output.txt"
    ptr_ips="$(dig +short A "${domain}" 2>/dev/null | grep -Eo "${IPv4_regex}" | head -3)"
    if [[ -z "${ptr_ips}" ]]; then
        echo "Done!"
        return 0
    fi
    while IFS= read -r ptr_ip; do
        [[ -z "${ptr_ip}" ]] && continue
        ptr_base="$(echo "${ptr_ip}" | awk -F'.' '{print $1"."$2"."$3}')"
        echo -e "\ndig: PTR sweep for /24 block of ${ptr_ip} (${ptr_base}.0/24)" >> "${log_execution_file}"
        for ptr_last in $(seq 1 254); do
            ptr_result="$(dig +short -x "${ptr_base}.${ptr_last}" 2>/dev/null | sed 's/\.$//' | tr '[:upper:]' '[:lower:]')"
            if [[ -n "${ptr_result}" ]]; then
                echo "${ptr_result}" >> "${tmp_dir}/ptr_sweep_output.txt"
            fi
        done
    done <<< "${ptr_ips}"
    echo "Done!"
}

ptr-sweep-src
