#!/bin/bash
###########################################################################
# Those functions try to get all data as possible from a web application  #
#                                                                         #
# This file is an essential part of collector's execution!                #
# And is responsible to get the functions:                                #
#                                                                         #
#   * crawler_js                                                          #
#   * crawler_params                                                      #
#                                                                         #
###########################################################################

crawler_js(){
    local target="$1"
    local urls_file="$2"
    local js_files="${tmp_dir}/js_files.tmp"
    local domain_re="${target//./\\.}"
    local user_agent subdomain js_url js_abs js_file_dir js_file_name js_status scheme host base

    echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Initializing the web application js crawler and this might take a certain time!"
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing js crawler... "

    if [ "$#" != 2 ] || [ ! -s "${urls_file}" ]; then
        echo "Fail!"
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Please, especify just 1 file to get URL from."
        echo -e "Please, especify just 1 file to get URL from." | notify "${notify_options[@]}" -id "${notify_recon_channel}" > /dev/null 2>&1
        message "${target}" failed
        return 1
    fi

    if [ ! -d "${report_dir}" ] || [ ! -d "${webapp_js_dir}" ]; then
        echo "Fail!"
        return 1
    fi

    while IFS= read -r subdomain; do
        [[ -z "${subdomain}" ]] && continue

        # webapp_consolidated.txt entries already carry scheme://host[:port]. Derive
        # the base URL once so relative srcs resolve correctly.
        scheme="$(echo "${subdomain}" | awk -F: '{print $1}')"
        host="$(echo "${subdomain}" | awk -F/ '{print $3}')"
        base="${scheme}://${host}"

        user_agent="$(get_user_agent)"

        # Source 1: parse <script src="..."> from the page itself.
        echo "curl ${curl_options[@]} -H \"User-agent: ${user_agent}\" -L \"${subdomain}\"" >> "${log_execution_file}"
        while IFS= read -r js_url; do
            [[ -z "${js_url}" ]] && continue
            if [[ "${js_url}" =~ ^https?:// ]]; then
                js_abs="${js_url}"
            elif [[ "${js_url}" == //* ]]; then
                js_abs="${scheme}:${js_url}"
            elif [[ "${js_url}" == /* ]]; then
                js_abs="${base}${js_url}"
            else
                js_abs="${base}/${js_url}"
            fi
            echo "${js_abs}" >> "${js_files}"
        done < <(curl "${curl_options[@]}" -H "User-agent: ${user_agent}" -L "${subdomain}" 2>> "${log_execution_file}" \
                    | grep -Eohi 'src=["'\''][^"'\'' >]+\.js[^"'\'' >]*' \
                    | sed -E 's/^src=["'\'']//')

        # Source 2: getJS. webapp_consolidated.txt already has scheme, no double prefix.
        echo "echo \"${subdomain}\" | getJS -complete >> ${js_files}" >> "${log_execution_file}"
        echo "${subdomain}" | getJS -complete >> "${js_files}" 2>> "${log_execution_file}"

        # Source 3: katana.
        echo "katana ${katana_options[@]} -u ${subdomain} >> ${js_files}" >> "${log_execution_file}"
        katana "${katana_options[@]}" -u "${subdomain}" >> "${js_files}" 2>> "${log_execution_file}"

        # Source 4: urlfinder. Pass just the host to -d.
        echo "urlfinder ${urlfinder_options[@]} -d ${host} >> ${js_files}" >> "${log_execution_file}"
        urlfinder "${urlfinder_options[@]}" -d "${host}" >> "${js_files}" 2>> "${log_execution_file}"

        # Source 5: waybackurls. Feed the host, not the URL with scheme.
        echo "echo \"${host}\" | waybackurls >> ${js_files}" >> "${log_execution_file}"
        echo "${host}" | waybackurls >> "${js_files}" 2>> "${log_execution_file}"
    done < "${urls_file}"

    # Fetch every unique .js URL whose host matches the target (any subdomain
    # of ${target}). 3rd-party CDN bundles are ignored to keep the report
    # focused on the target's own code.
    if [[ -s "${js_files}" ]]; then
        while IFS= read -r js_url; do
            [[ -z "${js_url}" ]] && continue
            [[ "${js_url}" =~ ^https?:// ]] || continue

            js_file_dir="$(echo "${js_url}" | awk -F/ '{print $3}')"
            [[ "${js_file_dir}" =~ (^|\.)${domain_re}(:[0-9]+)?$ ]] || continue

            js_file_name="$(basename "${js_url}" | awk -F'?' '{print $1}' | awk -F'#' '{print $1}')"
            [[ -z "${js_file_name}" ]] && continue
            [[ ! -d "${webapp_js_dir}/${js_file_dir}" ]] && mkdir -p "${webapp_js_dir}/${js_file_dir}"
            [[ -s "${webapp_js_dir}/${js_file_dir}/${js_file_name}" ]] && continue

            user_agent="$(get_user_agent)"

            # Probe with the fast profile so dead/slow hosts don't stall the
            # crawl. Use GET with --range 0-0 instead of HEAD: many CDNs lie
            # to HEAD or 405 it.
            js_status=$(curl "${curl_options_fast[@]}" -H "User-agent: ${user_agent}" -L -o /dev/null -w "%{http_code}" --range 0-0 "${js_url}" 2>> "${log_execution_file}")
            if [[ "${js_status}" =~ ^2[0-9]{2}$ ]]; then
                echo "curl ${curl_options[@]} -H \"User-agent: ${user_agent}\" -L \"${js_url}\" > \"${webapp_js_dir}/${js_file_dir}/${js_file_name}\"" >> "${log_execution_file}"
                curl "${curl_options[@]}" -H "User-agent: ${user_agent}" -L "${js_url}" > "${webapp_js_dir}/${js_file_dir}/${js_file_name}" 2>> "${log_execution_file}"
            fi
        done < <(grep -Eoi 'https?://[^[:space:]"'\''<>]+\.js([?#][^[:space:]"'\''<>]*)?' "${js_files}" | sort -u)
    fi

    echo "Done!"

    # Post-process: scan everything we just downloaded for hardcoded
    # credentials, API keys, JWTs, etc.
    scan_js_secrets "${webapp_js_dir}" "${report_dir}/webapp_js_secrets.txt"
}

crawler_params(){
    local target="$1"
    local urls_file="$2"
    local url name file

    echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Initializing the web application params crawler and this might take a certain time!"
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing params crawler... "

    if [ "$#" != 2 ] || [ ! -s "${urls_file}" ]; then
        echo "Fail!"
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Please, especify just 1 file to get URL from."
        echo -e "Please, especify just 1 file to get URL from." | notify "${notify_options[@]}" -id "${notify_recon_channel}" > /dev/null 2>&1
        message "${target}" failed
        return 1
    fi

    if [ ! -d "${webapp_params_dir}" ]; then
        echo "Fail!"
        return 1
    fi

    while IFS= read -r url; do
        [[ -z "${url}" ]] && continue
        name="$(echo "${url}" | sed -e "s/http:\/\//http_/" -e "s/https:\/\//https_/" -e "s/:/_/" -e "s/\/$//" -e "s/\//_/g")"
        file="${webapp_params_dir}/${name}.params"

        # Truncate the per-URL output so reruns don't accumulate stale entries.
        : > "${file}"

        echo "echo ${url} | waybackurls >> ${file}" >> "${log_execution_file}"
        echo "${url}" | waybackurls >> "${file}" 2>> "${log_execution_file}"

        echo "echo ${url} | katana -silent -nc -timeout ${katana_timeout} -c ${katana_threads} -p ${katana_threads} -f qurl -d 10 >> ${file}" >> "${log_execution_file}"
        echo "${url}" | katana -silent -nc -timeout "${katana_timeout}" -c "${katana_threads}" -p "${katana_threads}" -f qurl -d 10 2>> "${log_execution_file}" \
            | grep -E "^http" >> "${file}"

        # Final dedupe in place.
        [[ -s "${file}" ]] && sort -u -o "${file}" "${file}"
    done < "${urls_file}"

    echo "Done!"

    # Post-process: flag parameter names / DOM sinks in the JS that
    # crawler_js already downloaded — SQLi/XSS/SSRF/XXE/CMD/etc candidates.
    scan_js_params "${webapp_js_dir}" "${report_dir}/webapp_js_params.txt"
}
