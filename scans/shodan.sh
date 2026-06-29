#!/bin/bash
#############################################################
# Submit target IPs to Shodan for an on-demand scan         #
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * shodan_scan                                           #
#                                                           #
#############################################################

shodan_scan(){
    if [ "${shodan_use}" == "yes" ] && [ -s "${report_dir}/infra_blocks.txt" ]; then
        echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing shodan scan on target's IPs... "
        local shodan_scans
        shodan_scans=$(shodan info | grep "Scan.*:" | awk '{print $4}')
        # collector.cfg defines `shodan_just_scan_main_domain`; the previous
        # check on `shodan_scan_main_domain` was always false, so this branch
        # never executed (report B-09).
        if [ "${shodan_just_scan_main_domain}" == "yes" ] && [ "${shodan_scans}" -gt 1 ]; then
            local IP
            for IP in $(cat "${report_dir}/infra_ipv4.txt"); do
                echo "shodan scan submit ${IP} > ${shodan_dir}/shodan_scan.txt" >> "${log_execution_file}"
                "shodan" scan submit "${IP}" > "${shodan_dir}/shodan_scan.txt" 2>> "${log_execution_file}" &
            done
        fi
        echo "Done!"
    fi
}
