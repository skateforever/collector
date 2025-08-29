check_binaries(){
    # Verifying if all binaries there are in the system
    count=0
    for binary in amass aquatone censys-subdomain-finder.py diff dig dirsearch dnssearch git-dumper \
        gobuster host html2text jq katana massdns nmap notify nuclei shodan subfinder waybackurls whois; do
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

    if [ -n "${shodan_use}" ]; then
        shodan_use=$(echo "${shodan_use}" | tr '[:upper:]' '[:lower:]')
        if [ "${shodan_use}" == "yes" ]; then
            [[ -n "${shodan_just_scan_main_domain}" ]] && \
                shodan_just_scan_main_domain=$(echo "${shodan_just_scan_main_domain}" | tr '[:upper:]' '[:lower:]')
            if [ -n "${shodan_apikey}" ] && [ ! -s ~/.shodan/api_key ]; then
                shodan init "${shodan_apikey}" > /dev/null
            fi
        fi
    fi
}
