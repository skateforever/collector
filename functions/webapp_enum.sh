#!/bin/bash
###########################################################################
# Those functions try to get all data as possible from a web application  #
#                                                                         #
# This file is an essential part of collector's execution!                #
# And is responsible to get the functions:                                #
#                                                                         #
#   * webapp_enum                                                         #
#   * webapp_tech                                                         #
#   * robots_txt                                                          #
#                                                                         #
########################################################################### 

webapp_enum(){
    local target="$1"
    local urls_file="$2"
    local list index urls_tested url name file_gobuster file_dirsearch file_ffuf ffuf_ext_param
    echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Initializing the web application enumeration and this might take a certain time!"
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing web application files and dirs enumeration... "
    if [ -s "${urls_file}" ]; then
        if [ -d "${report_dir}" ]  && [ -d "${webapp_enum_dir}" ] ; then
            echo -e "${red}Warning:${reset} It can take a long time to execute the enumeration!"
            echo -e "\t We have $(wc -l "${urls_file}" | awk '{print $1}') urls to scan and ${#webapp_wordlists[@]} wordlist(s) to run."
            if [ ${#webapp_wordlists[@]} -gt 0 ]; then
                echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Web application enumeration will use ${#webapp_wordlists[@]} wordlists with ffuf, gobuster and dirsearch... "
                # ffuf consumes extensions one-shot via -e ".php,.bak,..." (with
                # leading dots); gobuster/dirsearch accept the comma-list raw.
                ffuf_ext_param=".$(echo "${webapp_file_extensions}" | sed 's/,/,./g')"
                for list in "${webapp_wordlists[@]}"; do
                    index=$(printf "%s\n" "${webapp_wordlists[@]}" | grep -En "^""${list}""$" | awk -F":" '{print $1}')
                    urls_tested=1
                    if [ -s "${list}" ]; then
                        while IFS= read -r url; do
                            # Mounting the file names
                            name="$(echo "${url}" | sed -e "s/http:\/\//http_/" -e "s/https:\/\//https_/" -e "s/:/_/" -e "s/\/$//" -e "s/\//_/g")"
                            file_gobuster="${name}.gobuster.${index}"
                            file_dirsearch="${name}.dirsearch.${index}"
                            file_ffuf="${name}.ffuf.${index}"
                            if [ -n "${use_proxy}" ] && [ "${use_proxy}" == "yes" ]; then
                                echo "dirsearch -t \"${dirsearch_threads}\" -e \"${webapp_file_extensions}\" --random-agent --no-color --quiet-mode \
                                    -w \"${list}\" --proxy \"${proxy_ip}\" --timeout=20 -u \"${url}\"" >> "${log_execution_file}"
                                dirsearch -t "${dirsearch_threads}" -e "${webapp_file_extensions}" --random-agent --no-color --quiet-mode \
                                    -w "${list}" --proxy "${proxy_ip}" --timeout=20 \
                                    -u "${url}" >> "${webapp_enum_dir}/${file_dirsearch}" 2>> "${log_execution_file}" &
                                echo "gobuster dir --quiet --no-color --no-error -z -k -e --timeout 20s --delay 300ms \
                                    --proxy http://${proxy_ip} -t ${gobuster_threads} -u ${url} -w ${list} \
                                    -x ${webapp_file_extensions} >> ${webapp_enum_dir}/${file_gobuster}" >> "${log_execution_file}"
                                gobuster dir --quiet --no-color --no-error -z -k -e --timeout 20s --delay 300ms \
                                    --proxy "http://${proxy_ip}" -t "${gobuster_threads}" \
                                    -u "${url}" -w "${list}" -x "${webapp_file_extensions}" \
                                    >> "${webapp_enum_dir}/${file_gobuster}" 2>> "${log_execution_file}" &
                                echo "ffuf ${ffuf_options[@]} -t ${ffuf_threads} -timeout 20 -H \"User-Agent: $(get_user_agent)\" \
                                    -x http://${proxy_ip} -w ${list}:FUZZ -e ${ffuf_ext_param} -u ${url}/FUZZ \
                                    -o ${webapp_enum_dir}/${file_ffuf}" >> "${log_execution_file}"
                                ffuf "${ffuf_options[@]}" -t "${ffuf_threads}" -timeout 20 -H "User-Agent: $(get_user_agent)" \
                                    -x "http://${proxy_ip}" -w "${list}:FUZZ" -e "${ffuf_ext_param}" \
                                    -u "${url}/FUZZ" -o "${webapp_enum_dir}/${file_ffuf}" 2>> "${log_execution_file}" &
                            else
                                echo "dirsearch -t \"${dirsearch_threads}\" -e \"${webapp_file_extensions}\" --random-agent \
                                    --no-color --quiet-mode -w \"${list}\" -u \"${url}\"" >> "${log_execution_file}"
                                dirsearch -t "${dirsearch_threads}" -e "${webapp_file_extensions}" --random-agent --no-color --quiet-mode \
                                    -w "${list}" -u "${url}" >> "${webapp_enum_dir}/${file_dirsearch}" 2>> "${log_execution_file}" &
                                echo "gobuster dir --quiet --no-color --no-error -z -k -e --timeout 20s --delay 300ms \
                                    -t ${gobuster_threads} -u ${url} -w ${list} -x ${webapp_file_extensions} \
                                    >> ${webapp_enum_dir}/${file_gobuster}" >> "${log_execution_file}"
                                gobuster dir --quiet --no-color --no-error -z -k -e --timeout 20s --delay 300ms \
                                    -t "${gobuster_threads}" -u "${url}" -w "${list}" -x "${webapp_file_extensions}" \
                                    >> "${webapp_enum_dir}/${file_gobuster}" 2>> "${log_execution_file}" &
                                echo "ffuf ${ffuf_options[@]} -t ${ffuf_threads} -timeout 20 -H \"User-Agent: $(get_user_agent)\" \
                                    -w ${list}:FUZZ -e ${ffuf_ext_param} -u ${url}/FUZZ \
                                    -o ${webapp_enum_dir}/${file_ffuf}" >> "${log_execution_file}"
                                ffuf "${ffuf_options[@]}" -t "${ffuf_threads}" -timeout 20 -H "User-Agent: $(get_user_agent)" \
                                    -w "${list}:FUZZ" -e "${ffuf_ext_param}" \
                                    -u "${url}/FUZZ" -o "${webapp_enum_dir}/${file_ffuf}" 2>> "${log_execution_file}" &
                            fi
                            while [[ "$(pgrep -acf "[d]irsearch.*${target}|[g]obuster.*${target}|[f]fuf.*${target}")" -ge "${webapp_enum_total_processes}" ]]; do
                                sleep 1
                            done
                            [[ -n "${limit_urls}" && "${limit_urls}" -eq "${urls_tested}" ]] && break
                            (( urls_tested+=1 ))
                            unset file_dirsearch
                            unset file_gobuster
                            unset file_ffuf
                            unset name
                            unset url
                        done < "${urls_file}"
                    else
                        echo -e "\t\t    ${red}Error:${reset} ${list} does not exist or is empty!"
                        echo -e "Error: ${list} does not exist or is empty!" | notify "${notify_options[@]}" -id "${notify_files_channel}"
                        continue
                    fi
                    unset index
                    unset list
                    unset urls_tested
                done
                echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Waiting the dirsearch, gobuster and ffuf finish... "
                while pgrep -af "[d]irsearch.*${target}" > /dev/null \
                    || pgrep -af "[g]obuster.*${target}" > /dev/null \
                    || pgrep -af "[f]fuf.*${target}" > /dev/null; do
                    sleep 1
                done
                echo "Done!"

                echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Cleaning up dirsearch files... "
                # Use find -exec instead of `sed -i ... "${dir}/*.dirsearch*"`:
                # double-quoted strings are not glob-expanded, so the previous
                # sed received a literal "/path/*.dirsearch*" filename and
                # silently failed (report B-10).
                find "${webapp_enum_dir}" -maxdepth 1 -type f -name '*.dirsearch*' -exec \
                    sed -i -e 's/.\[4.m//g' -e 's/.\[3.m//g' -e 's/.\[1K.\[0G/\n/g' \
                        -e 's/.\[1m//g' -e 's/.\[0m//g' -e '/Last request to/d' {} + 2> /dev/null
                echo "Done!"

                echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Cleaning up gobuster files... "
                find "${webapp_enum_dir}" -maxdepth 1 -type f -name '*.gobuster*' -exec \
                    sed -i "s/^..\[2K//" {} + 2> /dev/null
                echo "Done!"

                # ffuf CSV files: keep them as-is (they're already clean +
                # parseable). No sed pass needed. Header line is dropped by
                # the grep filters below.

                # Notifying the finds
                echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Sending files search notification... "
                grep --color=never -Ehr "^\[.*\] 200 -" "${webapp_enum_dir}/" | awk '{print $6}' | grep -E "($(echo ${webapp_file_extensions} | sed 's/,/|/g'))$" | notify "${notify_options[@]}" -id "${notify_files_channel}" > /dev/null 2>&1
                grep --color=never -Ehr "\(Status: 200\)" "${webapp_enum_dir}/" | awk '{print $1}' | grep -E "($(echo ${webapp_file_extensions} | sed 's/,/|/g'))$" | notify "${notify_options[@]}" -id "${notify_files_channel}" > /dev/null 2>&1
                # ffuf csv: FUZZ,url,redirectlocation,position,status_code,content_length,content_words,content_lines,content_type,duration,resultfile
                # Pull only 200 hits whose URL ends in a watched extension.
                find "${webapp_enum_dir}" -maxdepth 1 -type f -name '*.ffuf.*' -exec \
                    awk -F',' 'NR>1 && $5=="200" {print $2}' {} + 2>/dev/null \
                    | grep -E "($(echo ${webapp_file_extensions} | sed 's/,/|/g'))$" \
                    | notify "${notify_options[@]}" -id "${notify_files_channel}" > /dev/null 2>&1
                echo "Done!"
            else
                echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Array of wordlists is empty. Stopping the script!"
                echo -e "Array of wordlists is empty. Stopping the script!" | notify "${notify_options[@]}" -id "${notify_recon_channel}" > /dev/null 2>&1
                message "${target}" failed
                exit 1
            fi
        else
            echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Make sure the directories structure was created. Stopping the script!"
            echo -e "Make sure the directories structure was created. Stopping the script!" | notify "${notify_options[@]}" -id "${notify_recon_channel}" > /dev/null 2>&1
            message "${target}" failed
            exit 1
        fi
    else
        echo "Fail!"
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Make sure the ${urls_file} exist and isn't empty. You probably forgot to add --webapp-discovery option to execute, or really, we have a problem with script execution."
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} You probably forgot to add --webapp-discovery option to execute, or really, we have a problem with script execution."
        echo -e "Make sure the ${urls_file} exist and isn't empty. \nYou probably forgot to add --webapp-discovery option to execute, or really, we have a problem with script execution." | notify "${notify_options[@]}" -id "${notify_recon_channel}" > /dev/null 2>&1
        message "${target}" failed
        exit 1
    fi
    echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Web application enumeration is done!"
}

webapp_tech(){
    local target="$1"
    local urls_file="$2"
    local url name file_tech_by_headers
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing web application technology enumeration..."
    if [ -s "${urls_file}" ]; then
        if [ -d "${report_dir}" ] && [ -d "${webapp_tech_dir}" ] ; then
            # Explicit proxy arg arrays (the previous alias-based approach
            # never expanded in non-interactive scripts — see B-04).
            local -a curl_proxy_args=() httpx_proxy_args=()
            if [ -n "${use_proxy}" ] && [ "${use_proxy}" == "yes" ]; then
                curl_proxy_args=(--proxy "${proxy_ip}")
                httpx_proxy_args=(-http-proxy "${proxy_ip}")
            fi

            httpx -no-color -silent -update > /dev/null 2>&1
            while IFS= read -r url; do
                unset user_agent
                user_agent="$(get_user_agent)"
                name="$(echo "${url}" | sed -e "s/http:\/\//http_/" -e "s/https:\/\//https_/" -e "s/:/_/" -e "s/\/$//" -e "s/\//_/g")"
                file_tech_by_headers="${name}.tech"

                echo "curl ${curl_options[@]} ${curl_proxy_args[*]} -H \"User-agent: ${user_agent}\" -I \"${url}\"" >> "${log_execution_file}"
                curl "${curl_options[@]}" "${curl_proxy_args[@]}" -H "User-agent: ${user_agent}" -I "${url}" >> "${webapp_tech_dir}/${file_tech_by_headers}" 2>> "${log_execution_file}"

                echo "echo ${url} | httpx ${httpx_options[@]} ${httpx_proxy_args[*]} -title -tech-detect" >> "${log_execution_file}"
                echo "${url}" | httpx "${httpx_options[@]}" "${httpx_proxy_args[@]}" -title -tech-detect >> "${webapp_tech_dir}/${file_tech_by_headers}" 2>> "${log_execution_file}"

                unset file_tech_by_headers
                unset name
                unset url
            done < "${urls_file}"
            echo "Done!"
        fi
    else
        echo "Fail!"
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Make sure the ${urls_file} exist and isn't empty."
        echo -e "Make sure the ${urls_file} exist and isn't empty." | notify "${notify_options[@]}" -id "${notify_recon_channel}" > /dev/null 2>&1
        message "${target}" failed
        exit 1
    fi
}

robots_txt(){
    local robots_target url user_agent file
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Looking for new URLs on robots.txt... "
    while IFS= read -r -d '' file; do
        file="$(basename "${file}")"
        [[ ! -s "${webapp_enum_dir}/${file}" ]] && continue
        if grep -qE "robots\.txt" "${webapp_enum_dir}/${file}"; then
            robots_target=$(grep -E "Target:|Url:" "${webapp_enum_dir}/${file}" | sed -e 's/^\[+\] //' | awk '{print $2}' | head -1 | sed -e 's/\/$//')
            [[ -z "${robots_target}" ]] && continue
            user_agent="$(get_user_agent)"
            curl "${curl_options[@]}" -H "User-agent: ${user_agent}" -s "${robots_target}/robots.txt" 2>/dev/null \
                | grep -Ev "^[[:space:]]*(User-agent|#|$)" \
                | awk '{print $2}' \
                | sed -e '/^\/$/d' -e 's/\r//g' -e 's/\/$//' \
                | while IFS= read -r url; do
                    [[ -z "${url}" ]] && continue
                    echo "${robots_target}${url}"
                done >> "${report_dir}/robots_urls.txt"
        fi
    done < <(find "${webapp_enum_dir}" -maxdepth 1 -type f -print0)
    [[ -s "${report_dir}/robots_urls.txt" ]] && sort -u -o "${report_dir}/robots_urls.txt" "${report_dir}/robots_urls.txt"
    echo "Done!"
}

# Mirror of robots_txt for sitemap.xml: pulls /sitemap.xml from each live URL
# in webapp_consolidated.txt, follows <sitemapindex> entries recursively, and
# emits one URL per line to ${report_dir}/sitemap_urls.txt.
#
# Recursion is bounded by SITEMAP_MAX_DEPTH (default 3) and SITEMAP_MAX_INDEX
# (default 50) to avoid blow-up on hostile / very large sitemaps. xmllint is
# preferred when available for robust XML parsing; we fall back to grep so the
# function still works on minimal images that don't ship libxml2-utils.
#
# Also picks up Sitemap: hints from any robots.txt body that webapp_enum may
# have already captured into ${webapp_enum_dir} via dirsearch/gobuster/ffuf.
sitemap_xml(){
    local urls_file="${1:-${report_dir}/webapp_consolidated.txt}"
    local out_file="${report_dir}/sitemap_urls.txt"
    local seen_file="${tmp_dir}/sitemap_seen.tmp"
    local queue_file="${tmp_dir}/sitemap_queue.tmp"
    local body_file="${tmp_dir}/sitemap_body.tmp"
    local sm_url base_url depth max_depth max_index seeded
    local user_agent
    local -i processed=0

    max_depth="${SITEMAP_MAX_DEPTH:-3}"
    max_index="${SITEMAP_MAX_INDEX:-50}"

    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Looking for new URLs on sitemap.xml... "

    if [[ ! -s "${urls_file}" ]]; then
        echo "Skip (no URL list)."
        return 0
    fi

    : > "${seen_file}"
    : > "${queue_file}"
    seeded=0

    # Seed 1: <base>/sitemap.xml for every live URL.
    while IFS= read -r base_url; do
        [[ -z "${base_url}" ]] && continue
        base_url="${base_url%/}"
        sm_url="${base_url}/sitemap.xml"
        if ! grep -qFx "${sm_url}" "${seen_file}" 2>/dev/null; then
            printf '%s\t%d\n' "${sm_url}" 0 >> "${queue_file}"
            echo "${sm_url}" >> "${seen_file}"
            seeded=$((seeded + 1))
        fi
    done < "${urls_file}"

    # Seed 2: Sitemap: hints from robots.txt bodies captured during enum.
    if [[ -d "${webapp_enum_dir}" ]]; then
        while IFS= read -r sm_url; do
            [[ -z "${sm_url}" ]] && continue
            sm_url="$(echo "${sm_url}" | tr -d '\r' | sed -E 's/^[[:space:]]*[Ss]itemap[[:space:]]*:[[:space:]]*//' | awk '{print $1}')"
            [[ "${sm_url}" =~ ^https?:// ]] || continue
            if ! grep -qFx "${sm_url}" "${seen_file}" 2>/dev/null; then
                printf '%s\t%d\n' "${sm_url}" 0 >> "${queue_file}"
                echo "${sm_url}" >> "${seen_file}"
                seeded=$((seeded + 1))
            fi
        done < <(grep -EhIi '^[[:space:]]*Sitemap[[:space:]]*:' "${webapp_enum_dir}"/* 2>/dev/null | sort -u)
    fi

    if [[ "${seeded}" -eq 0 ]]; then
        echo "Skip (no sitemap candidates)."
        return 0
    fi

    # BFS over <sitemapindex> children, breadth bounded by max_index.
    while [[ -s "${queue_file}" ]] && [[ "${processed}" -lt "${max_index}" ]]; do
        IFS=$'\t' read -r sm_url depth < "${queue_file}"
        # Pop the head off the queue.
        tail -n +2 "${queue_file}" > "${queue_file}.tmp" && mv "${queue_file}.tmp" "${queue_file}"
        [[ -z "${sm_url}" ]] && continue
        processed=$((processed + 1))

        user_agent="$(get_user_agent)"
        echo "curl ${curl_options[@]} -H \"User-agent: ${user_agent}\" -L \"${sm_url}\"" >> "${log_execution_file}"
        : > "${body_file}"
        curl "${curl_options[@]}" -L -H "User-agent: ${user_agent}" "${sm_url}" -o "${body_file}" 2>> "${log_execution_file}" || continue
        [[ ! -s "${body_file}" ]] && continue

        # Extract <loc>...</loc> values. Prefer xmllint for correctness; fall
        # back to grep so we don't hard-depend on libxml2-utils inside the
        # image. Both paths emit raw URLs to stdout.
        local locs
        if command -v xmllint >/dev/null 2>&1; then
            locs="$(xmllint --xpath '//*[local-name()="loc"]/text()' "${body_file}" 2>/dev/null \
                | tr -d '\r' | tr '\t' '\n' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' | grep -E '^https?://' || true)"
        else
            locs="$(grep -oE '<loc[^>]*>[^<]+</loc>' "${body_file}" 2>/dev/null \
                | sed -E 's@<loc[^>]*>([^<]+)</loc>@\1@' | tr -d '\r' \
                | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' | grep -E '^https?://' || true)"
        fi

        [[ -z "${locs}" ]] && continue

        # If the document is itself an index (<sitemapindex>), the <loc>s
        # point at child sitemaps — enqueue them if we still have depth.
        # Otherwise (<urlset>) the <loc>s are page URLs — emit to out_file.
        if grep -qiE '<sitemapindex[[:space:]>]' "${body_file}" 2>/dev/null; then
            if [[ "${depth}" -lt "${max_depth}" ]]; then
                while IFS= read -r child; do
                    [[ -z "${child}" ]] && continue
                    if ! grep -qFx "${child}" "${seen_file}" 2>/dev/null; then
                        printf '%s\t%d\n' "${child}" "$((depth + 1))" >> "${queue_file}"
                        echo "${child}" >> "${seen_file}"
                    fi
                done <<< "${locs}"
            fi
        else
            # Treat anything that isn't an index as a urlset (handles sitemaps
            # without an explicit <urlset> root — RSS-flavoured variants, etc.).
            while IFS= read -r url; do
                [[ -z "${url}" ]] && continue
                # Strip fragment + trailing slash to match the robots_txt
                # output style; downstream tooling normalises further.
                url="${url%%#*}"
                url="${url%/}"
                echo "${url}" >> "${out_file}"
            done <<< "${locs}"
        fi
    done

    rm -f "${body_file}" "${queue_file}" "${seen_file}"

    if [[ -s "${out_file}" ]]; then
        sort -u -o "${out_file}" "${out_file}"
        echo "Done! ($(wc -l < "${out_file}") URLs)"
    else
        echo "Done! (no URLs extracted)"
    fi
}
