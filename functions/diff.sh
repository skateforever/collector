#!/bin/bash
#############################################################
# Getting the difference between old and new files          #
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * diff_domains                                          #
#   * diff_artifacts                                        #
#   * record_history                                        #
#                                                           #
#############################################################

# Locate the most recent prior run's copy of a given report file for the
# current domain. Returns empty string if no baseline exists.
diff_locate_baseline(){
    local name="$1"
    [[ -z "${name}" ]] && return 0
    find "${output_dir}/${domain}" -mindepth 3 -maxdepth 5 -type f -name "${name}" 2>/dev/null \
        | grep -v "/${date_recon}/" \
        | sort \
        | tail -n1
}

# Apply ${output_dir}/${domain}/domains_ignore.txt as a fixed-string blocklist.
# Reads stdin, writes stdout.
diff_apply_ignore(){
    local ignore="${output_dir}/${domain}/domains_ignore.txt"
    if [[ -s "${ignore}" ]]; then
        local pat
        pat="$(mktemp "${tmp_dir}/diff_ignore.XXXXXX")"
        grep -Ev '^[[:space:]]*(#|$)' "${ignore}" > "${pat}" || true
        if [[ -s "${pat}" ]]; then
            grep -Fxv -f "${pat}"
        else
            cat
        fi
        rm -f "${pat}"
    else
        cat
    fi
}

# Generic delta detector. Emits a human-readable diff file and notifies the
# recon channel only when something actually changed.
# Args: label, current_file, output_diff_file, max_lines_in_notify (default 50)
diff_file(){
    local label="$1"
    local new="$2"
    local diff_out="$3"
    local cap="${4:-50}"
    local name baseline added removed added_n removed_n

    name="$(basename "${new}")"
    : > "${diff_out}"

    [[ ! -s "${new}" ]] && return 0

    baseline="$(diff_locate_baseline "${name}")"
    if [[ -z "${baseline}" ]]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} No baseline for ${label} (first run)."
        return 0
    fi

    added="$(mktemp "${tmp_dir}/diff_${label}_added.XXXXXX")"
    removed="$(mktemp "${tmp_dir}/diff_${label}_removed.XXXXXX")"

    comm -13 <(sort -u "${baseline}" | diff_apply_ignore) <(sort -u "${new}" | diff_apply_ignore) > "${added}"
    comm -23 <(sort -u "${baseline}" | diff_apply_ignore) <(sort -u "${new}" | diff_apply_ignore) > "${removed}"

    added_n="$(wc -l < "${added}" | awk '{print $1}')"
    removed_n="$(wc -l < "${removed}" | awk '{print $1}')"

    {
        if [[ "${added_n}" -gt 0 ]]; then
            echo "## Added since $(basename "$(dirname "$(dirname "${baseline}")")")"
            cat "${added}"
        fi
        if [[ "${removed_n}" -gt 0 ]]; then
            [[ "${added_n}" -gt 0 ]] && echo
            echo "## Removed since $(basename "$(dirname "$(dirname "${baseline}")")")"
            cat "${removed}"
        fi
    } > "${diff_out}"

    if [[ "${added_n}" -gt 0 ]] || [[ "${removed_n}" -gt 0 ]]; then
        {
            echo "Recon diff for ${domain} — ${label}"
            echo "Baseline: ${baseline}"
            echo "Added:    ${added_n}"
            echo "Removed:  ${removed_n}"
            if [[ "${added_n}" -gt 0 ]]; then
                echo
                echo "+ NEW (showing up to ${cap}):"
                head -n "${cap}" "${added}" | sed 's/^/+ /'
                [[ "${added_n}" -gt "${cap}" ]] && echo "+ ... ($(( added_n - cap )) more)"
            fi
            if [[ "${removed_n}" -gt 0 ]]; then
                echo
                echo "- GONE (showing up to ${cap}):"
                head -n "${cap}" "${removed}" | sed 's/^/- /'
                [[ "${removed_n}" -gt "${cap}" ]] && echo "- ... ($(( removed_n - cap )) more)"
            fi
        } | notify -nc -silent -id "${notify_recon_channel}" > /dev/null 2>&1
    fi

    rm -f "${added}" "${removed}"
}

diff_domains(){
    if [[ ! -d "${report_dir}" ]]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Make sure the directories structure was created."
        echo "The error occurred in the function diff_domains.sh!" | notify -nc -silent -id "${notify_recon_channel}" > /dev/null 2>&1
        message "${domain}" failed
        return 1
    fi

    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Computing subdomain diff vs. previous run... "
    if [[ ! -s "${report_dir}/domains_found.txt" ]]; then
        echo "Fail!"
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} File ${report_dir}/domains_found.txt does not exist or is empty!"
        echo "The error occurred in the function diff_domains.sh!" | notify -nc -silent -id "${notify_recon_channel}" > /dev/null 2>&1
        return 1
    fi

    diff_file "subdomains" "${report_dir}/domains_found.txt" "${report_dir}/domains_diff.txt"
    echo "Done!"
}

diff_artifacts(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Computing artifact diffs vs. previous run... "

    [[ -s "${report_dir}/infra_ipv4.txt" ]] && \
        diff_file "ips" "${report_dir}/infra_ipv4.txt" "${report_dir}/infra_ipv4_diff.txt"

    [[ -s "${report_dir}/webapp_urls.txt" ]] && \
        diff_file "webapp_urls" "${report_dir}/webapp_urls.txt" "${report_dir}/webapp_urls_diff.txt"

    [[ -n "${nuclei_scan_file}" && -s "${nuclei_scan_file}" ]] && \
        diff_file "nuclei" "${nuclei_scan_file}" "${nuclei_scan_file%.result}_diff.txt"

    [[ -s "${report_dir}/email_recon.txt" ]] && \
        diff_file "emails" "${report_dir}/email_recon.txt" "${report_dir}/email_recon_diff.txt"

    [[ -s "${report_dir}/vhost_subdomains.txt" ]] && \
        diff_file "vhosts" "${report_dir}/vhost_subdomains.txt" "${report_dir}/vhost_subdomains_diff.txt"

    echo "Done!"
}

# Append one observability row per execution to the per-domain history CSV.
# Always called, regardless of whether there was a diff this run.
record_history(){
    local hist="${output_dir}/${domain}/_history.csv"
    local subs ips vhosts_strong vhosts_weak emails high crit urls

    subs="0";          [[ -s "${report_dir}/domains_found.txt"        ]] && subs="$(wc -l < "${report_dir}/domains_found.txt"        | awk '{print $1}')"
    ips="0";           [[ -s "${report_dir}/infra_ipv4.txt"           ]] && ips="$(wc -l < "${report_dir}/infra_ipv4.txt"           | awk '{print $1}')"
    vhosts_strong="0"; [[ -s "${report_dir}/vhost_subdomains.txt"     ]] && vhosts_strong="$(wc -l < "${report_dir}/vhost_subdomains.txt"     | awk '{print $1}')"
    vhosts_weak="0";   [[ -s "${report_dir}/vhost_subdomains_weak.txt" ]] && vhosts_weak="$(wc -l < "${report_dir}/vhost_subdomains_weak.txt" | awk '{print $1}')"
    urls="0";          [[ -s "${report_dir}/webapp_urls.txt"          ]] && urls="$(wc -l < "${report_dir}/webapp_urls.txt"          | awk '{print $1}')"
    emails="0";        [[ -s "${report_dir}/email_recon.txt"          ]] && emails="$(wc -l < "${report_dir}/email_recon.txt"          | awk '{print $1}')"
    high="0";          [[ -n "${nuclei_scan_file}" && -s "${nuclei_scan_file}" ]] && high="$(grep -c '\[high\]'     "${nuclei_scan_file}" || true)"
    crit="0";          [[ -n "${nuclei_scan_file}" && -s "${nuclei_scan_file}" ]] && crit="$(grep -c '\[critical\]' "${nuclei_scan_file}" || true)"

    if [[ ! -s "${hist}" ]]; then
        echo "date_recon,subdomains,ips,webapp_urls,vhosts_strong,vhosts_weak,emails,findings_high,findings_critical" > "${hist}"
    fi
    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s\n' "${date_recon}" "${subs}" "${ips}" "${urls}" "${vhosts_strong}" "${vhosts_weak}" "${emails}" "${high}" "${crit}" >> "${hist}"
}
