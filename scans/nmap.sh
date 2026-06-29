#!/bin/bash
#############################################################
# Port scan over the target's IPv4 surface                  #
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * nmap_scan                                             #
#                                                           #
#############################################################

nmap_scan(){
        if [ -s "${report_dir}/infra_ipv4.txt" ]; then
            echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Getting information about IPs with nmap... "
            echo -e "\nnmap ${nmap_options[@]} -iL \"${report_dir}/infra_ipv4.txt\" > \"${nmap_dir}/nmap_scan.txt\"" >> "${log_execution_file}"
            nmap "${nmap_options[@]}" -iL "${report_dir}/infra_ipv4.txt" > "${nmap_dir}/nmap_scan.txt"
            echo "Done!"
        fi
}
