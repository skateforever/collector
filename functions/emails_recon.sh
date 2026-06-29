#!/bin/bash
#############################################################
# Try to make a email recon                                 #
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * emails_recon                                          #
#                                                           #
#############################################################

# Extract emails from a body file and keep only those whose domain matches the
# current target (domain itself or any subdomain). Appends matches to $2.
emails_filter_to_target(){
    local body_file="$1"
    local out_file="$2"
    local domain_re="${domain//./\\.}"
    grep -EhoI "${webapp_email_regex}" "${body_file}" 2>/dev/null \
        | grep -iE "@([A-Za-z0-9._-]+\.)?${domain_re}$" >> "${out_file}" 2>/dev/null || true
}

emails_recon(){
    local emails_tmp="${tmp_dir}/email_recon.tmp"
    local emails_out="${report_dir}/email_recon.txt"
    local urls_file="${report_dir}/webapp_consolidated.txt"
    local body_file="${tmp_dir}/email_recon_body.tmp"
    local js_file="${tmp_dir}/email_recon_js.tmp"
    local user_agent
    local max_js url js_url js_count js_abs scheme host base

    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Looking for emails to help during blackbox pentest... "

    if [[ -z "${domain}" ]] || [[ ! -d "${tmp_dir}" ]] || [[ ! -d "${report_dir}" ]]; then
        echo "Fail!"
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} emails_recon: missing domain or directories."
        return 1
    fi

    : > "${emails_tmp}"

    # Hunter.io
    if [[ -n "${hunterio_api}" ]] && [[ -n "${hunterio_api_url}" ]]; then
        user_agent="$(get_user_agent)"
        echo "$(redact_secrets "curl ${curl_options[@]} -H \"User-agent: ${user_agent}\" \"${hunterio_api_url}?domain=${domain}&api_key=${hunterio_api}\"")" >> "${log_execution_file}"
        curl "${curl_options[@]}" -H "User-agent: ${user_agent}" "${hunterio_api_url}?domain=${domain}&api_key=${hunterio_api}" 2>> "${log_execution_file}" \
            | jq -r '.data.emails[]?.value // empty' 2>> "${log_execution_file}" >> "${emails_tmp}"
    fi

    # Lampyre
    if [[ -n "${lampyre_api_key}" ]] && [[ -n "${lampyre_api_url}" ]]; then
        user_agent="$(get_user_agent)"
        echo "$(redact_secrets "curl ${curl_options[@]} -H \"User-agent: ${user_agent}\" -H \"lt-token: ${lampyre_api_key}\" -H \"Content-Type: application/json\" --data '{\"request_type\":\"domain_emails\",\"domain\":\"${domain}\"}' \"${lampyre_api_url}\"")" >> "${log_execution_file}"
        curl "${curl_options[@]}" -H "User-agent: ${user_agent}" -H "lt-token: ${lampyre_api_key}" -H "Content-Type: application/json" --data "{\"request_type\":\"domain_emails\",\"domain\":\"${domain}\"}" "${lampyre_api_url}" 2>> "${log_execution_file}" \
            | grep -EhoI "${webapp_email_regex}" 2>/dev/null >> "${emails_tmp}"
    fi

    # Snov.io
    if [[ -n "${snov_api_token}" ]] && [[ -n "${snov_api_url}" ]]; then
        user_agent="$(get_user_agent)"
        echo "$(redact_secrets "curl ${curl_options[@]} -H \"User-agent: ${user_agent}\" -H \"Authorization: Bearer ${snov_api_token}\" \"${snov_api_url}?domain=${domain}&type=all&limit=100\"")" >> "${log_execution_file}"
        curl "${curl_options[@]}" -H "User-agent: ${user_agent}" -H "Authorization: Bearer ${snov_api_token}" "${snov_api_url}?domain=${domain}&type=all&limit=100" 2>> "${log_execution_file}" \
            | jq -r '.emails[]?.email // .data.emails[]?.email // empty' 2>> "${log_execution_file}" >> "${emails_tmp}"
    fi

    # IntelX — phonebook two-step lookup. Step 1 POSTs the search and gets an
    # `id`; step 2 GETs /phonebook/result?id=... to fetch the actual selectors.
    # We use target=2 (email phonebook); sources/intelx.sh uses target=1
    # (URL phonebook) for subdomain enrichment, so the two queries are
    # orthogonal and can share the same API key.
    #
    # The result payload nests email values under .selectors[].selectorvalue.
    # We accept any value that LOOKS like an email — the host-suffix filter
    # downstream (tr → grep -EohI webapp_email_regex) drops mismatches.
    if [[ -n "${intelx_api_key}" ]] && [[ -n "${intelx_api_url}" ]]; then
        local intelx_search_id intelx_search_body
        user_agent="$(get_user_agent)"
        echo "$(redact_secrets "curl ${curl_options[@]} -H \"User-agent: ${user_agent}\" -H \"Content-Type: application/json\" -X POST \"${intelx_api_url}/phonebook/search?k=${intelx_api_key}\" -d '{\"term\":\"${domain}\",\"buckets\":[],\"lookuplevel\":0,\"maxresults\":${intelx_emails_max_results:-10000},\"timeout\":0,\"datefrom\":\"\",\"dateto\":\"\",\"sort\":4,\"media\":0,\"terminate\":[],\"target\":2}'")" >> "${log_execution_file}"
        intelx_search_body="$(curl "${curl_options[@]}" \
            -H "User-agent: ${user_agent}" \
            -H "Content-Type: application/json" \
            -X POST "${intelx_api_url}/phonebook/search?k=${intelx_api_key}" \
            -d "{\"term\":\"${domain}\",\"buckets\":[],\"lookuplevel\":0,\"maxresults\":${intelx_emails_max_results:-10000},\"timeout\":0,\"datefrom\":\"\",\"dateto\":\"\",\"sort\":4,\"media\":0,\"terminate\":[],\"target\":2}" \
            2>> "${log_execution_file}")"
        intelx_search_id="$(echo "${intelx_search_body}" | jq -r '.id // empty' 2>/dev/null)"
        if [[ -n "${intelx_search_id}" ]]; then
            # IntelX needs a beat to populate the result buffer; polling is
            # available via status=1 but a fixed sleep matches the pattern
            # already used by sources/intelx.sh and keeps the code simple.
            sleep 3
            echo "$(redact_secrets "curl ${curl_options_slow[@]} -H \"User-agent: ${user_agent}\" \"${intelx_api_url}/phonebook/result?k=${intelx_api_key}&id=${intelx_search_id}&limit=${intelx_emails_max_results:-10000}&offset=0\"")" >> "${log_execution_file}"
            # Slow profile because /phonebook/result can stream a lot of rows
            # for popular domains; default profile would time out at 60s.
            curl "${curl_options_slow[@]}" \
                -H "User-agent: ${user_agent}" \
                "${intelx_api_url}/phonebook/result?k=${intelx_api_key}&id=${intelx_search_id}&limit=${intelx_emails_max_results:-10000}&offset=0" 2>> "${log_execution_file}" \
                | jq -r '.selectors[]?.selectorvalue // empty' 2>> "${log_execution_file}" >> "${emails_tmp}"
        else
            echo "intelx phonebook search returned no id (rate-limited, bad key, or no hits)" >> "${log_execution_file}"
        fi
    fi

    # Webapp crawl: page roots + referenced JS
    if [[ -s "${urls_file}" ]]; then
        max_js="${webapp_email_max_js_per_url:-20}"
        while IFS= read -r url; do
            [[ -z "${url}" ]] && continue
            user_agent="$(get_user_agent)"
            : > "${body_file}"
            echo "curl ${curl_options[@]} -L -H \"User-agent: ${user_agent}\" \"${url}\"" >> "${log_execution_file}"
            curl "${curl_options[@]}" -L -H "User-agent: ${user_agent}" "${url}" -o "${body_file}" 2>> "${log_execution_file}" || true
            emails_filter_to_target "${body_file}" "${emails_tmp}"

            scheme="$(echo "${url}" | awk -F: '{print $1}')"
            host="$(echo "${url}" | awk -F/ '{print $3}')"
            base="${scheme}://${host}"

            js_count=0
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

                echo "curl ${curl_options[@]} -L -H \"User-agent: ${user_agent}\" \"${js_abs}\"" >> "${log_execution_file}"
                : > "${js_file}"
                curl "${curl_options[@]}" -L -H "User-agent: ${user_agent}" "${js_abs}" -o "${js_file}" 2>> "${log_execution_file}" || true
                emails_filter_to_target "${js_file}" "${emails_tmp}"

                (( js_count+=1 ))
                [[ "${js_count}" -ge "${max_js}" ]] && break
            done < <(grep -EohI 'src=["'\''][^"'\'' >]+\.js[^"'\'' >]*' "${body_file}" 2>/dev/null | sed -E 's/^src=["'\'']//' | sort -u)
        done < "${urls_file}"

        rm -f "${body_file}" "${js_file}"
    fi

    # Consolidate -> ${report_dir}/email_recon.txt
    if [[ -s "${emails_tmp}" ]]; then
        tr '[:upper:]' '[:lower:]' < "${emails_tmp}" | grep -EohI "${webapp_email_regex}" | sort -u >> "${emails_out}"
        sort -u -o "${emails_out}" "${emails_out}"
    fi

    echo "Done!"
}
