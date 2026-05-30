#!/bin/bash
#############################################################
# Getting the difference between old and new files          #
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * diff_domains                                          #
#   * diff_artifacts (infra/webapp/nuclei/email)            #
#   * record_history                                        #
#                                                           #
# Variable scoping policy:                                  #
#   * Function-private state declared with `local` at top.  #
#   * Globals consumed (never reassigned) from collector    #
#     orchestration: domain, output_dir, report_dir,        #
#     date_recon, log_execution_file, notify_recon_channel, #
#     yellow, red, reset, nuclei_scan_file.                 #
#############################################################

# Locate the most recent prior run's copy of a given report file for the
# current domain. "Prior" means: a run on a date directory that is NOT
# today's (${date_recon}). Returns empty string if no baseline exists.
#
# Args: $1 = basename of the file to look up (e.g. "domains_found.txt")
# Echoes: absolute path to the baseline file, or empty.
_diff_locate_baseline(){
    local _name="$1"
    [[ -z "${_name}" ]] && return 0
    find "${output_dir}/${domain}" -mindepth 3 -maxdepth 5 \
        -type f -name "${_name}" 2>/dev/null \
        | grep -v "/${date_recon}/" \
        | sort \
        | tail -n1
}

# Apply ${output_dir}/${domain}/domains_ignore.txt (if present) as a
# fixed-string blocklist. Lines starting with '#' or blank are ignored.
# Reads stdin, writes stdout.
_diff_apply_ignore(){
    local _ignore="${output_dir}/${domain}/domains_ignore.txt"
    if [[ -s "${_ignore}" ]]; then
        # Build a sanitized pattern file in tmp; -F = fixed strings, -x =
        # whole-line match, -v = invert. Comments and blanks are stripped.
        local _pat
        _pat="$(mktemp "${tmp_dir}/diff_ignore.XXXXXX")"
        grep -Ev '^[[:space:]]*(#|$)' "${_ignore}" > "${_pat}" || true
        if [[ -s "${_pat}" ]]; then
            grep -Fxv -f "${_pat}"
        else
            cat
        fi
        rm -f "${_pat}"
    else
        cat
    fi
}

# Generic delta detector. Emits a human-readable diff file and notifies
# the recon channel only when something actually changed.
#
# Args:
#   $1 = label              (e.g. "subdomains", "ips", "webapp_urls")
#   $2 = current file       (absolute path inside ${report_dir})
#   $3 = output diff file   (absolute path)
#   $4 = max lines per side in notify body (cap to avoid flooding chat)
_diff_file(){
    local _label="$1"
    local _new="$2"
    local _diff_out="$3"
    local _cap="${4:-50}"
    local _name _baseline _added _removed _added_n _removed_n

    _name="$(basename "${_new}")"

    # Always truncate the diff output for this run.
    : > "${_diff_out}"

    if [[ ! -s "${_new}" ]]; then
        return 0
    fi

    _baseline="$(_diff_locate_baseline "${_name}")"
    if [[ -z "${_baseline}" ]]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} No baseline for ${_label} (first run)."
        return 0
    fi

    _added="$(mktemp "${tmp_dir}/diff_${_label}_added.XXXXXX")"
    _removed="$(mktemp "${tmp_dir}/diff_${_label}_removed.XXXXXX")"

    # comm requires sorted input. The ignore-list filter is applied to BOTH
    # sides so re-adding an ignored entry never resurfaces as "new".
    comm -13 \
        <(sort -u "${_baseline}" | _diff_apply_ignore) \
        <(sort -u "${_new}"      | _diff_apply_ignore) > "${_added}"
    comm -23 \
        <(sort -u "${_baseline}" | _diff_apply_ignore) \
        <(sort -u "${_new}"      | _diff_apply_ignore) > "${_removed}"

    _added_n="$(wc -l < "${_added}" | awk '{print $1}')"
    _removed_n="$(wc -l < "${_removed}" | awk '{print $1}')"

    {
        if [[ "${_added_n}" -gt 0 ]]; then
            echo "## Added since $(basename "$(dirname "$(dirname "${_baseline}")")")"
            cat "${_added}"
        fi
        if [[ "${_removed_n}" -gt 0 ]]; then
            [[ "${_added_n}" -gt 0 ]] && echo
            echo "## Removed since $(basename "$(dirname "$(dirname "${_baseline}")")")"
            cat "${_removed}"
        fi
    } > "${_diff_out}"

    if [[ "${_added_n}" -gt 0 ]] || [[ "${_removed_n}" -gt 0 ]]; then
        {
            echo "Recon diff for ${domain} — ${_label}"
            echo "Baseline: ${_baseline}"
            echo "Added:    ${_added_n}"
            echo "Removed:  ${_removed_n}"
            if [[ "${_added_n}" -gt 0 ]]; then
                echo
                echo "+ NEW (showing up to ${_cap}):"
                head -n "${_cap}" "${_added}" | sed 's/^/+ /'
                [[ "${_added_n}" -gt "${_cap}" ]] && echo "+ ... ($(( _added_n - _cap )) more)"
            fi
            if [[ "${_removed_n}" -gt 0 ]]; then
                echo
                echo "- GONE (showing up to ${_cap}):"
                head -n "${_cap}" "${_removed}" | sed 's/^/- /'
                [[ "${_removed_n}" -gt "${_cap}" ]] && echo "- ... ($(( _removed_n - _cap )) more)"
            fi
        } | notify -nc -silent -id "${notify_recon_channel}" > /dev/null 2>&1
    fi

    rm -f "${_added}" "${_removed}"
}

# Subdomain delta — kept as a thin wrapper for backward compatibility with
# the orchestrator (domains_recon.sh) which checks domains_diff.txt.
diff_domains(){
    if [[ ! -d "${report_dir}" ]]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Make sure the directories structure was created."
        echo "The error occurred in the function diff_domains.sh!" \
            | notify -nc -silent -id "${notify_recon_channel}" > /dev/null 2>&1
        message "${domain}" failed
        return 1
    fi

    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Computing subdomain diff vs. previous run... "
    if [[ ! -s "${report_dir}/domains_found.txt" ]]; then
        echo "Fail!"
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} File ${report_dir}/domains_found.txt does not exist or is empty!"
        echo "The error occurred in the function diff_domains.sh!" \
            | notify -nc -silent -id "${notify_recon_channel}" > /dev/null 2>&1
        return 1
    fi

    _diff_file "subdomains" \
        "${report_dir}/domains_found.txt" \
        "${report_dir}/domains_diff.txt"
    echo "Done!"
}

# Run the generic diff over every artifact that is worth alerting on.
# Called from the orchestrator AFTER all producers have finished.
diff_artifacts(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Computing artifact diffs vs. previous run... "

    [[ -s "${report_dir}/infra_ipv4.txt" ]] && \
        _diff_file "ips" \
            "${report_dir}/infra_ipv4.txt" \
            "${report_dir}/infra_ipv4_diff.txt"

    [[ -s "${report_dir}/webapp_urls.txt" ]] && \
        _diff_file "webapp_urls" \
            "${report_dir}/webapp_urls.txt" \
            "${report_dir}/webapp_urls_diff.txt"

    [[ -n "${nuclei_scan_file}" && -s "${nuclei_scan_file}" ]] && \
        _diff_file "nuclei" \
            "${nuclei_scan_file}" \
            "${nuclei_scan_file%.result}_diff.txt"

    [[ -s "${report_dir}/email_recon.txt" ]] && \
        _diff_file "emails" \
            "${report_dir}/email_recon.txt" \
            "${report_dir}/email_recon_diff.txt"

    [[ -s "${report_dir}/vhost_subdomains.txt" ]] && \
        _diff_file "vhosts" \
            "${report_dir}/vhost_subdomains.txt" \
            "${report_dir}/vhost_subdomains_diff.txt"

    echo "Done!"
}

# Append one observability row per execution to the per-domain history CSV.
# Always called, regardless of whether there was a diff this run — the CSV
# is for trend analysis, not for change alerts.
record_history(){
    local _hist="${output_dir}/${domain}/_history.csv"
    local _subs _ips _vhosts_strong _vhosts_weak _emails _high _crit _urls

    _subs="0";          [[ -s "${report_dir}/domains_found.txt"        ]] && _subs="$(wc -l < "${report_dir}/domains_found.txt"        | awk '{print $1}')"
    _ips="0";           [[ -s "${report_dir}/infra_ipv4.txt"           ]] && _ips="$(wc -l < "${report_dir}/infra_ipv4.txt"           | awk '{print $1}')"
    _vhosts_strong="0"; [[ -s "${report_dir}/vhost_subdomains.txt"     ]] && _vhosts_strong="$(wc -l < "${report_dir}/vhost_subdomains.txt"     | awk '{print $1}')"
    _vhosts_weak="0";   [[ -s "${report_dir}/vhost_subdomains_weak.txt" ]] && _vhosts_weak="$(wc -l < "${report_dir}/vhost_subdomains_weak.txt" | awk '{print $1}')"
    _urls="0";          [[ -s "${report_dir}/webapp_urls.txt"          ]] && _urls="$(wc -l < "${report_dir}/webapp_urls.txt"          | awk '{print $1}')"
    _emails="0";        [[ -s "${report_dir}/email_recon.txt"          ]] && _emails="$(wc -l < "${report_dir}/email_recon.txt"          | awk '{print $1}')"
    _high="0";          [[ -n "${nuclei_scan_file}" && -s "${nuclei_scan_file}" ]] && _high="$(grep -c '\[high\]'     "${nuclei_scan_file}" || true)"
    _crit="0";          [[ -n "${nuclei_scan_file}" && -s "${nuclei_scan_file}" ]] && _crit="$(grep -c '\[critical\]' "${nuclei_scan_file}" || true)"

    # Header on first run only.
    if [[ ! -s "${_hist}" ]]; then
        echo "date_recon,subdomains,ips,webapp_urls,vhosts_strong,vhosts_weak,emails,findings_high,findings_critical" > "${_hist}"
    fi
    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
        "${date_recon}" "${_subs}" "${_ips}" "${_urls}" \
        "${_vhosts_strong}" "${_vhosts_weak}" "${_emails}" \
        "${_high}" "${_crit}" \
        >> "${_hist}"
}
