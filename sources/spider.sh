#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * spider-src                                            #
#                                                           #
#############################################################

spider-src(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing spider... "
    : > "${tmp_dir}/spider_output.txt"
    unset user_agent
    user_agent="$(get_user_agent)"
    local spider_visited=()
    local spider_queue=()
    local spider_fetched=0
    local spider_max_pages=100
    local spider_max_depth=3
    local spider_max_js=40

    # Seed: fetch root page (https first, http fallback)
    local spider_root_url=""
    local spider_root_body=""
    for spider_scheme in https http; do
        echo -e "\ncurl ${curl_options[@]} -H \"User-agent: ${user_agent}\" \"${spider_scheme}://${domain}\"" >> "${log_execution_file}"
        spider_root_body="$(curl "${curl_options[@]}" -L \
            -H "User-agent: ${user_agent}" \
            -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
            "${spider_scheme}://${domain}" 2>> "${log_execution_file}")"
        if [[ -n "${spider_root_body}" ]]; then
            spider_root_url="${spider_scheme}://${domain}"
            break
        fi
    done

    [[ -z "${spider_root_url}" ]] && { echo "Done!"; return 0; }

    # Extract subdomains from root page
    echo "${spider_root_body}" | grep -Eo '[a-zA-Z0-9._-]+\.'"${domain}" \
        | tr '[:upper:]' '[:lower:]' >> "${tmp_dir}/spider_output.txt"

    # Collect same-domain links for BFS
    local spider_js_urls=()
    local spider_js_seen=()

    _spider_collect_links(){
        local spider_body="$1"
        local spider_base="$2"
        local spider_depth="$3"
        # href links (a, link tags)
        echo "${spider_body}" | grep -oiE '(href|src)="[^"#]+"' | grep -oE '"[^"]+"' | tr -d '"' | while IFS= read -r spider_href; do
            [[ "${spider_href}" =~ ^https?:// ]] || spider_href="${spider_base%/}/${spider_href#/}"
            echo "${spider_href}" | grep -E "https?://[a-zA-Z0-9._-]*${domain}" | sed "s|#.*||"
        done
    }

    _spider_collect_js(){
        local spider_body="$1"
        local spider_base="$2"
        echo "${spider_body}" | grep -oiE 'src="[^"]+\.js[^"]*"' | grep -oE '"[^"]+"' | tr -d '"' | while IFS= read -r spider_jsref; do
            [[ "${spider_jsref}" =~ ^https?:// ]] || spider_jsref="${spider_base%/}/${spider_jsref#/}"
            echo "${spider_jsref}" | grep -E "https?://[a-zA-Z0-9._-]*${domain}"
        done
    }

    # Seed queue from root
    while IFS= read -r spider_link; do
        [[ -z "${spider_link}" ]] && continue
        if [[ ! " ${spider_visited[*]} " =~ " ${spider_link} " ]]; then
            spider_queue+=("${spider_link}:1")
            spider_visited+=("${spider_link}")
        fi
    done < <(_spider_collect_links "${spider_root_body}" "${spider_root_url}" 1)

    while IFS= read -r spider_js; do
        [[ -z "${spider_js}" ]] && continue
        [[ ! " ${spider_js_seen[*]} " =~ " ${spider_js} " ]] && { spider_js_urls+=("${spider_js}"); spider_js_seen+=("${spider_js}"); }
    done < <(_spider_collect_js "${spider_root_body}" "${spider_root_url}")

    # BFS crawl
    while [[ ${#spider_queue[@]} -gt 0 && "${spider_fetched}" -lt "${spider_max_pages}" ]]; do
        spider_entry="${spider_queue[0]}"
        spider_queue=("${spider_queue[@]:1}")
        spider_url="${spider_entry%:*}"
        spider_depth="${spider_entry##*:}"
        spider_fetched=$(( spider_fetched + 1 ))
        echo -e "\ncurl ${curl_options[@]} -H \"User-agent: ${user_agent}\" \"${spider_url}\"" >> "${log_execution_file}"
        spider_page_body="$(curl "${curl_options[@]}" -L \
            -H "User-agent: ${user_agent}" \
            -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
            "${spider_url}" 2>> "${log_execution_file}")"
        [[ -z "${spider_page_body}" ]] && continue
        echo "${spider_page_body}" | grep -Eo '[a-zA-Z0-9._-]+\.'"${domain}" \
            | tr '[:upper:]' '[:lower:]' >> "${tmp_dir}/spider_output.txt"
        while IFS= read -r spider_js; do
            [[ -z "${spider_js}" ]] && continue
            [[ ! " ${spider_js_seen[*]} " =~ " ${spider_js} " ]] && { spider_js_urls+=("${spider_js}"); spider_js_seen+=("${spider_js}"); }
        done < <(_spider_collect_js "${spider_page_body}" "${spider_url}")
        if [[ "${spider_depth}" -lt "${spider_max_depth}" ]]; then
            while IFS= read -r spider_link; do
                [[ -z "${spider_link}" ]] && continue
                if [[ ! " ${spider_visited[*]} " =~ " ${spider_link} " ]]; then
                    spider_queue+=("${spider_link}:$(( spider_depth + 1 ))")
                    spider_visited+=("${spider_link}")
                fi
            done < <(_spider_collect_links "${spider_page_body}" "${spider_url}" "${spider_depth}")
        fi
    done

    # Phase 3: download JS files and extract subdomains + sourcemap references
    local spider_js_count=0
    for spider_js_url in "${spider_js_urls[@]}"; do
        [[ "${spider_js_count}" -ge "${spider_max_js}" ]] && break
        spider_js_count=$(( spider_js_count + 1 ))
        echo -e "\ncurl ${curl_options[@]} -H \"User-agent: ${user_agent}\" \"${spider_js_url}\"" >> "${log_execution_file}"
        spider_js_body="$(curl "${curl_options[@]}" \
            -H "User-agent: ${user_agent}" \
            "${spider_js_url}" 2>> "${log_execution_file}")"
        [[ -z "${spider_js_body}" ]] && continue
        echo "${spider_js_body}" | grep -Eo '[a-zA-Z0-9._-]+\.'"${domain}" \
            | tr '[:upper:]' '[:lower:]' >> "${tmp_dir}/spider_output.txt"
        # Phase 4: sourcemap references
        spider_map_ref="$(echo "${spider_js_body}" | grep -oE '//[#@]\s*sourceMappingURL=[^\s"'"'"']+' | tail -1 | awk '{print $NF}' | sed 's/sourceMappingURL=//')"
        if [[ -n "${spider_map_ref}" && ! "${spider_map_ref}" =~ ^data: ]]; then
            [[ "${spider_map_ref}" =~ ^https?:// ]] || spider_map_ref="${spider_js_url%/*}/${spider_map_ref}"
            echo -e "\ncurl ${curl_options[@]} -H \"User-agent: ${user_agent}\" \"${spider_map_ref}\"" >> "${log_execution_file}"
            curl "${curl_options[@]}" \
                -H "User-agent: ${user_agent}" \
                "${spider_map_ref}" 2>> "${log_execution_file}" \
                | grep -Eo '[a-zA-Z0-9._-]+\.'"${domain}" \
                | tr '[:upper:]' '[:lower:]' >> "${tmp_dir}/spider_output.txt"
        fi
    done

    sort -u -o "${tmp_dir}/spider_output.txt" "${tmp_dir}/spider_output.txt" 2>/dev/null
    echo "Done!"
}

spider-src
