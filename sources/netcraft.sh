#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * netcraft-src                                          #
#                                                           #
#############################################################
#
# Scrapes searchdns.netcraft.com (free, no API key required).
# Paginates via &from=&last= parameters until no new results.
# Output: netcraft_output.txt — one subdomain per line.
#
#############################################################

netcraft-src(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing netcraft... "
    : > "${tmp_dir}/netcraft_output.txt"
    unset user_agent
    user_agent="$(get_user_agent)"

    local netcraft_base_url="https://searchdns.netcraft.com"
    local netcraft_url="${netcraft_base_url}/?restriction=site+contains&host=*.${domain}&position=limited"
    local netcraft_page netcraft_last netcraft_from
    local netcraft_max_pages=10
    local netcraft_page_count=0
    local netcraft_prev_count=0
    local netcraft_cur_count

    while [[ -n "${netcraft_url}" && "${netcraft_page_count}" -lt "${netcraft_max_pages}" ]]; do
        netcraft_page_count=$(( netcraft_page_count + 1 ))
        echo -e "\ncurl ${curl_options_slow[*]} -H \"User-agent: ${user_agent}\" \"${netcraft_url}\"" >> "${log_execution_file}"
        netcraft_page="$(curl "${curl_options_slow[@]}" \
            -H "User-agent: ${user_agent}" \
            -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
            -H "Referer: https://searchdns.netcraft.com/" \
            "${netcraft_url}" 2>> "${log_execution_file}")"

        # Extract subdomains from href links that point to individual host results
        # Pattern: href="https://searchdns.netcraft.com/?restriction=site+contains&host=sub.domain.com..."
        echo "${netcraft_page}" \
            | grep -oE 'href="https://searchdns\.netcraft\.com/\?[^"]*host=[a-zA-Z0-9._-]+\.'"${domain}"'[^"]*"' \
            | grep -oE 'host=[a-zA-Z0-9._-]+\.'"${domain}" \
            | sed 's/host=//' \
            | tr '[:upper:]' '[:lower:]' \
            >> "${tmp_dir}/netcraft_output.txt"

        # Check for a "next page" link — pattern: href="?...&from=X&last=X"
        netcraft_next="$(echo "${netcraft_page}" \
            | grep -oE 'href="\?[^"]*from=[^"&]+[^"]*"' \
            | tail -1 \
            | grep -oE '"\?[^"]*from=[^"&]+[^"]*"' \
            | tr -d '"')"

        if [[ -z "${netcraft_next}" ]]; then
            break
        fi

        # Sanity check: stop if result count hasn't grown (duplicate page / loop)
        netcraft_cur_count="$(wc -l < "${tmp_dir}/netcraft_output.txt")"
        if [[ "${netcraft_cur_count}" -le "${netcraft_prev_count}" ]]; then
            break
        fi
        netcraft_prev_count="${netcraft_cur_count}"

        netcraft_url="${netcraft_base_url}/${netcraft_next}"
        sleep 2
    done

    sort -u -o "${tmp_dir}/netcraft_output.txt" "${tmp_dir}/netcraft_output.txt" 2>/dev/null
    echo "Done!"
    sleep 1
}

netcraft-src
