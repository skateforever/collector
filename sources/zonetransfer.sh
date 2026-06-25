#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * zonetransfer                                          #
#                                                           #
#############################################################            

zonetransfer-src(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Trying to execute zone transfer... "
    for ns in $(dig +short ns "${domain}" 2> /dev/null | sed -e 's/\.$//'); do
        # Capture output once; check for failure indicators in the same pass.
        # Skip empty results too, so a silently-failing NS doesn't append a
        # blank newline to zone_transfer.txt.
        zt_result="$(dig axfr "@${ns}" "${domain}" 2>/dev/null)"
        if [[ -n "${zt_result}" ]] && ! echo "${zt_result}" | grep -qEi "Transfer failed\.|servers could be reached|timed out\.|network unreachable\."; then
            echo "${zt_result}" >> "${tmp_dir}/zone_transfer.txt"
        fi
        unset zt_result
    done
    echo "Done!"
}

zonetransfer-src
