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
    local urls_file="${report_dir}/webapp_urls.txt"
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
