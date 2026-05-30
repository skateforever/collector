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
#
# Variable scoping policy used in this file:
#   * Function-private state is always declared with `local` at the top of
#     the function. This prevents leakage into the caller's shell and stops
#     stray `unset` typos from clobbering globals.
#   * Globals consumed here come from collector.cfg or from the orchestrator
#     (collector main script): domain, tmp_dir, report_dir, log_execution_file,
#     curl_options, hunterio_api{,_url}, lampyre_api_{key,url},
#     snov_api_{token,url}, webapp_email_regex, webapp_email_max_js_per_url,
#     yellow/red/reset. Those are intentionally global and never reassigned
#     inside these functions.

# Extract emails from a body of text (HTML or JS) and keep only those whose
# domain matches the current target (domain itself or any subdomain).
# Args:
#   $1 - path to file with raw body
#   $2 - path to file where matches should be appended
_emails_filter_to_target(){
    local _body_file="$1"
    local _out_file="$2"
    local _domain_re
    # Escape dots in target domain for regex use.
    _domain_re="${domain//./\\.}"
    # Match either the bare domain or any subdomain prefix preceding it.
    grep -EhoI "${webapp_email_regex}" "${_body_file}" 2>/dev/null \
        | grep -iE "@([A-Za-z0-9._-]+\.)?${_domain_re}$" \
        >> "${_out_file}" 2>/dev/null || true
}

emails_recon(){
    # ---- locals ---------------------------------------------------------
    # Output / scratch files.
    local _emails_tmp="${tmp_dir}/email_recon.tmp"
    local _emails_out="${report_dir}/email_recon.txt"
    local _urls_file="${report_dir}/webapp_urls.txt"
    local _body_file="${tmp_dir}/email_recon_body.tmp"
    local _js_file="${tmp_dir}/email_recon_js.tmp"
    # Per-request user-agent — never leaked to the caller's shell.
    local user_agent
    # Crawl-loop state.
    local _max_js
    local url js_url js_count js_abs scheme host base
    # ---------------------------------------------------------------------

    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Looking for emails to help during blackbox pentest... "

    # Sanity: tmp/report dirs must exist; domain must be set.
    if [[ -z "${domain}" ]] || [[ ! -d "${tmp_dir}" ]] || [[ ! -d "${report_dir}" ]]; then
        echo "Fail!"
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} emails_recon: missing domain or directories."
        return 1
    fi

    # All intermediate hits (from every phase) accumulate here. Truncated at
    # the start of each run so reruns don't carry stale data.
    : > "${_emails_tmp}"

    ###########################################################
    # 1) Hunter.io                                            #
    ###########################################################
    if [[ -n "${hunterio_api}" ]] && [[ -n "${hunterio_api_url}" ]]; then
        user_agent="$(get_user_agent)"
        echo "$(redact_secrets "curl ${curl_options[@]} -H \"User-agent: ${user_agent}\" \"${hunterio_api_url}?domain=${domain}&api_key=${hunterio_api}\"")" \
            >> "${log_execution_file}"
        curl "${curl_options[@]}" -H "User-agent: ${user_agent}" \
            "${hunterio_api_url}?domain=${domain}&api_key=${hunterio_api}" 2>> "${log_execution_file}" \
            | jq -r '.data.emails[]?.value // empty' 2>> "${log_execution_file}" \
            >> "${_emails_tmp}"
    fi

    ###########################################################
    # 2) Lampyre                                              #
    ###########################################################
    if [[ -n "${lampyre_api_key}" ]] && [[ -n "${lampyre_api_url}" ]]; then
        user_agent="$(get_user_agent)"
        echo "$(redact_secrets "curl ${curl_options[@]} -H \"User-agent: ${user_agent}\" -H \"lt-token: ${lampyre_api_key}\" -H \"Content-Type: application/json\" --data '{\"request_type\":\"domain_emails\",\"domain\":\"${domain}\"}' \"${lampyre_api_url}\"")" \
            >> "${log_execution_file}"
        curl "${curl_options[@]}" -H "User-agent: ${user_agent}" \
            -H "lt-token: ${lampyre_api_key}" \
            -H "Content-Type: application/json" \
            --data "{\"request_type\":\"domain_emails\",\"domain\":\"${domain}\"}" \
            "${lampyre_api_url}" 2>> "${log_execution_file}" \
            | grep -EhoI "${webapp_email_regex}" 2>/dev/null \
            >> "${_emails_tmp}"
    fi

    ###########################################################
    # 3) Snov.io (static long-lived access token)             #
    ###########################################################
    if [[ -n "${snov_api_token}" ]] && [[ -n "${snov_api_url}" ]]; then
        user_agent="$(get_user_agent)"
        echo "$(redact_secrets "curl ${curl_options[@]} -H \"User-agent: ${user_agent}\" -H \"Authorization: Bearer ${snov_api_token}\" \"${snov_api_url}?domain=${domain}&type=all&limit=100\"")" \
            >> "${log_execution_file}"
        curl "${curl_options[@]}" -H "User-agent: ${user_agent}" \
            -H "Authorization: Bearer ${snov_api_token}" \
            "${snov_api_url}?domain=${domain}&type=all&limit=100" 2>> "${log_execution_file}" \
            | jq -r '.emails[]?.email // .data.emails[]?.email // empty' 2>> "${log_execution_file}" \
            >> "${_emails_tmp}"
    fi

    ###########################################################
    # 4) Webapp crawl: page roots from webapp_urls.txt + JS   #
    ###########################################################
    if [[ -s "${_urls_file}" ]]; then
        _max_js="${webapp_email_max_js_per_url:-20}"
        while IFS= read -r url; do
            [[ -z "${url}" ]] && continue
            user_agent="$(get_user_agent)"

            # Fetch page root HTML into the shared scratch body file.
            : > "${_body_file}"
            echo "curl ${curl_options[@]} -L -H \"User-agent: ${user_agent}\" \"${url}\"" \
                >> "${log_execution_file}"
            curl "${curl_options[@]}" -L -H "User-agent: ${user_agent}" \
                "${url}" -o "${_body_file}" 2>> "${log_execution_file}" || true

            # Mine emails from the page itself into the unified .tmp.
            _emails_filter_to_target "${_body_file}" "${_emails_tmp}"

            # Derive base URL (scheme://host[:port]) for resolving relative JS srcs.
            scheme="$(echo "${url}" | awk -F: '{print $1}')"
            host="$(echo "${url}" | awk -F/ '{print $3}')"
            base="${scheme}://${host}"

            # Extract referenced .js URLs (src="...js..." or src='...js...').
            # Cap to webapp_email_max_js_per_url.
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

                echo "curl ${curl_options[@]} -L -H \"User-agent: ${user_agent}\" \"${js_abs}\"" \
                    >> "${log_execution_file}"
                : > "${_js_file}"
                curl "${curl_options[@]}" -L -H "User-agent: ${user_agent}" \
                    "${js_abs}" -o "${_js_file}" 2>> "${log_execution_file}" || true
                _emails_filter_to_target "${_js_file}" "${_emails_tmp}"

                (( js_count+=1 ))
                [[ "${js_count}" -ge "${_max_js}" ]] && break
            done < <(grep -EohI 'src=["'\''][^"'\'' >]+\.js[^"'\'' >]*' "${_body_file}" 2>/dev/null \
                        | sed -E 's/^src=["'\'']//' | sort -u)
        done < "${_urls_file}"

        rm -f "${_body_file}" "${_js_file}"
    fi

    ###########################################################
    # Consolidate -> ${report_dir}/email_recon.txt            #
    ###########################################################
    if [[ -s "${_emails_tmp}" ]]; then
        # Lowercase, strip junk, dedupe into the final report file.
        tr '[:upper:]' '[:lower:]' < "${_emails_tmp}" \
            | grep -EohI "${webapp_email_regex}" \
            | sort -u >> "${_emails_out}"
        # Final dedupe in case the file already existed.
        sort -u -o "${_emails_out}" "${_emails_out}"
    fi

    echo "Done!"
}
