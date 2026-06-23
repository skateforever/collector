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

    [[ ! -s "${new}" ]] && return 0

    baseline="$(diff_locate_baseline "${name}")"
    if [[ -z "${baseline}" ]]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} No baseline for ${label} (first run)."
        return 0
    fi

    : > "${diff_out}"

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

    [[ -s "${report_dir}/webapp_consolidated.txt" ]] && \
        diff_file "webapp_consolidated" "${report_dir}/webapp_consolidated.txt" "${report_dir}/webapp_consolidated_diff.txt"

    [[ -n "${nuclei_scan_file}" && -s "${nuclei_scan_file}" ]] && \
        diff_file "nuclei" "${nuclei_scan_file}" "${nuclei_scan_file%.result}_diff.txt"

    [[ -s "${report_dir}/email_recon.txt" ]] && \
        diff_file "emails" "${report_dir}/email_recon.txt" "${report_dir}/email_recon_diff.txt"

    [[ -s "${report_dir}/etc_hosts_file.txt" ]] && \
        diff_file "vhosts" "${report_dir}/etc_hosts_file.txt" "${report_dir}/vhost_subdomains_diff.txt"

    echo "Done!"
}

# Append one observability row per execution to the per-domain history CSV.
# Always called, regardless of whether there was a diff this run.
#
# The file is named ${domain}_history.csv and lives at the per-target root
# (${output_dir}/${domain}/). It is the canonical input for loading collector
# results into any database: each row is one run, fully self-describing
# (target, run id/date, counts, deltas, paths to the underlying artifacts,
# bundle pointer, status). Loaders can COPY/INSERT it directly with the
# domain column as the foreign key.
#
# Schema (one row per run, header on first write):
#   domain               target FQDN — PK on the parent table
#   run_id               recon_YYYYMMDD basename (unique per domain+day)
#   run_date             ISO date YYYY-MM-DD
#   started_at           ISO 8601 with timezone
#   finished_at          ISO 8601 with timezone
#   mode                 recon|webapp-discovery|webapp-crawler|webapp-scan|webapp-enum|url
#   subdomains           count of domains_found.txt
#   subdomains_alive     count of domains_alive.txt
#   subdomains_added     count of domains_diff.txt (added since previous run)
#   ips                  count of infra_ipv4.txt
#   ips_added            count of infra_ipv4_diff.txt
#   webapp_consolidated       count of webapp_consolidated.txt
#   webapp_consolidated_added count of webapp_consolidated_diff.txt
#   vhosts_strong        count of vhost_subdomains.txt
#   vhosts_weak          count of vhost_subdomains_weak.txt
#   vhosts_added         count of vhost_subdomains_diff.txt
#   emails               count of email_recon.txt
#   emails_added         count of email_recon_diff.txt
#   js_secrets           count of webapp_js_secrets.txt (excluding header lines)
#   js_params            count of webapp_js_params.txt (excluding header lines)
#   findings_info        count of [info]     entries in nuclei_scan.result
#   findings_low         count of [low]      entries
#   findings_medium      count of [medium]   entries
#   findings_high        count of [high]     entries
#   findings_critical    count of [critical] entries
#   report_dir           absolute path to this run's report/ directory
#   llm_prompt_path      absolute path to llm-prompt.txt (empty if not built)
#   status               finished|partial
record_history(){
    local hist="${output_dir}/${domain}/${domain}_history.csv"
    local target="${domain:-${url_domain}}"
    local run_id finished_at mode
    local subs subs_alive subs_added ips ips_added urls urls_added
    local vhosts_strong vhosts_added emails emails_added
    local secrets params info low med high crit
    local llm_prompt status

    run_id="$(basename "${recon_dir}")"
    finished_at="$(date +"%Y-%m-%dT%H:%M:%S%z")"

    # Best-effort mode label so a DB can group runs by intent.
    if [[ "${url_check}" == "yes" ]]; then
        mode="url"
    elif [[ "${webapp_enum_check}" == "yes" ]]; then
        mode="webapp-enum"
    elif [[ "${webapp_scan_check}" == "yes" && "${recon_check}" != "yes" ]]; then
        mode="webapp-scan"
    elif [[ "${webapp_crawler_check}" == "yes" && "${recon_check}" != "yes" ]]; then
        mode="webapp-crawler"
    elif [[ "${webapp_discovery_check}" == "yes" && "${recon_check}" != "yes" ]]; then
        mode="webapp-discovery"
    elif [[ "${recon_check}" == "yes" ]]; then
        mode="recon"
    else
        mode="unknown"
    fi

    count_lines(){ [[ -s "$1" ]] && wc -l < "$1" | awk '{print $1}' || echo 0; }
    count_match(){ [[ -s "$1" ]] && grep -c "$2" "$1" 2>/dev/null || echo 0; }
    count_body(){ [[ -s "$1" ]] && grep -cv -E '^(#|$)' "$1" 2>/dev/null || echo 0; }

    subs="$(count_lines        "${report_dir}/domains_found.txt")"
    subs_alive="$(count_lines  "${report_dir}/domains_alive.txt")"
    subs_added="$(count_lines  "${report_dir}/domains_diff.txt")"
    ips="$(count_lines         "${report_dir}/infra_ipv4.txt")"
    ips_added="$(count_lines   "${report_dir}/infra_ipv4_diff.txt")"
    urls="$(count_lines        "${report_dir}/webapp_consolidated.txt")"
    urls_added="$(count_lines  "${report_dir}/webapp_consolidated_diff.txt")"
    vhosts_strong="$(count_lines "${report_dir}/etc_hosts_file.txt")"
    vhosts_added="$(count_lines  "${report_dir}/vhost_subdomains_diff.txt")"
    emails="$(count_lines        "${report_dir}/email_recon.txt")"
    emails_added="$(count_lines  "${report_dir}/email_recon_diff.txt")"
    secrets="$(count_body        "${report_dir}/webapp_js_secrets.txt")"
    params="$(count_body         "${report_dir}/webapp_js_params.txt")"

    info="0"; low="0"; med="0"; high="0"; crit="0"
    if [[ -n "${nuclei_scan_file}" && -s "${nuclei_scan_file}" ]]; then
        info="$(count_match "${nuclei_scan_file}" '\[info\]')"
        low="$(count_match  "${nuclei_scan_file}" '\[low\]')"
        med="$(count_match  "${nuclei_scan_file}" '\[medium\]')"
        high="$(count_match "${nuclei_scan_file}" '\[high\]')"
        crit="$(count_match "${nuclei_scan_file}" '\[critical\]')"
    fi

    llm_prompt=""
    [[ -s "${report_dir}/llm-claude-prompt.txt" ]] && llm_prompt="${report_dir}/llm-claude-prompt.txt"
    [[ -z "${llm_prompt}" && -s "${report_dir}/llm-local-prompt.txt" ]] && llm_prompt="${report_dir}/llm-local-prompt.txt"

    # Status is "finished" when build_llm_prompt produced its bundle —
    # that's the last step of every successful flow. Otherwise the run
    # ended early (failure / partial mode).
    status="partial"
    [[ -n "${llm_prompt}" ]] && status="finished"

    if [[ ! -s "${hist}" ]]; then
        echo "domain,run_id,run_date,started_at,finished_at,mode,subdomains,subdomains_alive,subdomains_added,ips,ips_added,webapp_consolidated,webapp_consolidated_added,vhosts_strong,vhosts_added,emails,emails_added,js_secrets,js_params,findings_info,findings_low,findings_medium,findings_high,findings_critical,report_dir,llm_prompt_path,status" > "${hist}"
    fi
    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
        "${target}" "${run_id}" "${run_date:-${date_recon}}" "${started_at:-}" "${finished_at}" "${mode}" \
        "${subs}" "${subs_alive}" "${subs_added}" \
        "${ips}" "${ips_added}" \
        "${urls}" "${urls_added}" \
        "${vhosts_strong}" "${vhosts_added}" \
        "${emails}" "${emails_added}" \
        "${secrets}" "${params}" \
        "${info}" "${low}" "${med}" "${high}" "${crit}" \
        "${report_dir}" "${llm_prompt}" "${status}" >> "${hist}"
}
