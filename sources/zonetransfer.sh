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
        for ns in $(dig +short ns "${domain}" 2> /dev/null | sed -e 's/\.$//'); do
            if ! dig axfr "@${ns}" "${domain}" 2> /dev/null | grep -Ei "Transfer failed.|servers could be reached|timed out.|network unreachable.$" > /dev/null 2>&1; then
                dig axfr "@${ns}" "${domain}" >> "${tmp_dir}/zone_transfer.txt" 2> /dev/null
            fi
        done
}

zonetransfer-src
