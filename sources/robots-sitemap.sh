#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * robots-sitemap-src                                    #
#                                                           #
#############################################################

robots-sitemap-src(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing robots/sitemap mining... "
    : > "${tmp_dir}/robots_sitemap_output.txt"
    unset user_agent
    user_agent="$(get_user_agent)"
    local robots_sitemap_queue=()
    local robots_sitemap_visited=()
    local robots_sitemap_fetched=0
    local robots_sitemap_max=20

    # Phase 1: fetch /robots.txt — extract Sitemap: directives and absolute URLs in Disallow/Allow
    for robots_scheme in https http; do
        echo -e "\ncurl ${curl_options[@]} -H \"User-agent: ${user_agent}\" \"${robots_scheme}://${domain}/robots.txt\"" >> "${log_execution_file}"
        robots_body="$(curl "${curl_options[@]}" -L \
            -H "User-agent: ${user_agent}" \
            "${robots_scheme}://${domain}/robots.txt" 2>> "${log_execution_file}")"
        if [[ -n "${robots_body}" ]]; then
            # Sitemap: directives
            while IFS= read -r robots_sitemap_url; do
                [[ -z "${robots_sitemap_url}" ]] && continue
                robots_sitemap_queue+=("${robots_sitemap_url}")
            done < <(echo "${robots_body}" | grep -iE '^Sitemap:' | awk '{print $2}')
            # Absolute URLs leaked in Disallow/Allow paths
            echo "${robots_body}" | grep -iE '^(Disallow|Allow):' | awk '{print $2}' \
                | grep -Eo 'https?://[^/" ]+' \
                | grep -Eo '[a-zA-Z0-9._-]+\.'"${domain}" \
                | tr '[:upper:]' '[:lower:]' >> "${tmp_dir}/robots_sitemap_output.txt"
            break
        fi
    done

    # If no Sitemap: found, try common locations
    if [[ ${#robots_sitemap_queue[@]} -eq 0 ]]; then
        robots_sitemap_queue=(
            "https://${domain}/sitemap.xml"
            "https://${domain}/sitemap_index.xml"
            "https://${domain}/sitemaps/sitemap.xml"
        )
    fi

    # Phase 2 + 3: fetch sitemaps and extract hostnames from <loc> entries
    while [[ ${#robots_sitemap_queue[@]} -gt 0 && "${robots_sitemap_fetched}" -lt "${robots_sitemap_max}" ]]; do
        robots_sitemap_url="${robots_sitemap_queue[0]}"
        robots_sitemap_queue=("${robots_sitemap_queue[@]:1}")
        # Skip already visited
        if [[ " ${robots_sitemap_visited[*]} " =~ " ${robots_sitemap_url} " ]]; then
            continue
        fi
        robots_sitemap_visited+=("${robots_sitemap_url}")
        robots_sitemap_fetched=$(( robots_sitemap_fetched + 1 ))
        echo -e "\ncurl ${curl_options[@]} -H \"User-agent: ${user_agent}\" \"${robots_sitemap_url}\"" >> "${log_execution_file}"
        robots_sitemap_body="$(curl "${curl_options[@]}" -L \
            -H "User-agent: ${user_agent}" \
            "${robots_sitemap_url}" 2>> "${log_execution_file}")"
        [[ -z "${robots_sitemap_body}" ]] && continue
        # <sitemapindex> — nested sitemaps
        while IFS= read -r robots_child_url; do
            [[ -z "${robots_child_url}" ]] && continue
            if [[ ! " ${robots_sitemap_visited[*]} " =~ " ${robots_child_url} " ]]; then
                robots_sitemap_queue+=("${robots_child_url}")
            fi
        done < <(echo "${robots_sitemap_body}" | sed -n 's|.*<sitemap>.*<loc>\([^<]*\)</loc>.*</sitemap>.*|\1|p')
        # <urlset> <loc> entries — extract hostnames
        echo "${robots_sitemap_body}" | sed -n 's|.*<loc>\([^<]*\)</loc>.*|\1|p' \
            | grep -Eo '[a-zA-Z0-9._-]+\.'"${domain}" \
            | tr '[:upper:]' '[:lower:]' >> "${tmp_dir}/robots_sitemap_output.txt"
    done

    sort -u -o "${tmp_dir}/robots_sitemap_output.txt" "${tmp_dir}/robots_sitemap_output.txt" 2>/dev/null
    echo "Done!"
}

robots-sitemap-src
