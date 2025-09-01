#!/bin/bash
#############################################################
# Verify if all binaries there are in the system            #
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * check_binaries                                        #
#                                                           #
#############################################################

check_binaries(){
    count=0
    for binary in amass aquatone censys-subdomain-finder.py curl diff dig dirsearch dnssearch git-dumper \
        gobuster host html2text httpx jq katana massdns nmap notify nuclei shodan subfinder tlsx waybackurls whois; do
    if ! command -v "${binary}" > /dev/null 2>&1 ; then
        echo -e "The ${red}${binary} does not exist${reset} on the system!"
        ((count += 1))
    fi
done

    # Get the correct path to use chromium with aquatone
    for binary in chromium chromium-browser; do
        if [ -x "$(command -v ${binary})" ] ; then
           chromium_bin="$(command -v ${binary})"
        fi
    done

    if [ -z "${chromium_bin}" ]; then
        echo -e "The ${red}chromium does not exist${reset} on the system!"
        ((count += 1))
    fi

    if [ "${count}" -gt 0 ]; then
        echo -e "Please, ${yellow}make sure${reset} you got all tools (binaries and scripts)."
        echo -e "You could use the ${yellow}get-tools.sh${reset} to get all binaries and scripts!"
        unset count
        exit 1
    fi
}
