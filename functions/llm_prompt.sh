#!/bin/bash
#############################################################
#                                                           #
# LLM prompt bundle builder.                                #
#                                                           #
# Concatenates every artifact produced by a recon run into  #
# ${report_dir}/llm-prompt.txt so the operator can paste    #
# (or upload) a single self-contained file to an LLM for    #
# triage/analysis. Sensitive fields (API keys configured    #
# in collector.cfg) are redacted via redact_secrets, which  #
# lives in utils.sh.                                        #
#                                                           #
# Exposes:                                                  #
#   * llm_emit_artifact   (per-file section writer)         #
#   * build_llm_prompt    (top-level orchestrator)          #
#                                                           #
#############################################################

# Internal helper: emits a delimited + optionally truncated section for
# one artifact file into an already-open output file descriptor.
# Args: $1=out_file $2=report_dir $3=relative_path $4=max_lines
llm_emit_artifact(){
    local out_file="$1" base="$2" rel="$3"
    local f="${base}/${rel}"
    [[ ! -s "${f}" ]] && return 0
    local line
    echo "===== BEGIN ${rel} =====" >> "${out_file}"
    while IFS= read -r line; do redact_secrets "${line}"; echo; done < "${f}" >> "${out_file}"
    echo "===== END ${rel} =====" >> "${out_file}"
    echo >> "${out_file}"
}

# Generates a single LLM prompt bundle from the current run containing all
# artifacts produced by collector. Written to ${report_dir}/llm-prompt.txt.
# Header is read from ${collector_path}/support/runtime/prompts/llm-header.txt with
# __TARGET__, __TS__ and __REPORT_DIR__ replaced at generation time.
build_llm_prompt(){
    local target="${domain:-${url_domain:-unknown}}"
    local ts="$(date +"%Y-%m-%d %H:%M:%S %z")"
    local rel f lines size
    local header_file="${collector_llm_header}"
    local out="${report_dir}/llm-prompt.txt"

    [[ ! -d "${report_dir}" ]] && return 0
    [[ ! -s "${header_file}" ]] && { echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} build_llm_prompt: header template missing → ${header_file}"; return 1; }

    local -a artifacts=(
        "domains_found.txt"
        "domains_diff.txt"
        "domains_alive.txt"
        "domains_without_resolution.txt"
        "domains_excluded.txt"
        "domains_aliases.txt"
        "domains_thirdpart.txt"
        "domains_infrastructure.txt"
        "domains_internal_ipv4.txt"
        "domains_external_ipv4.txt"
        "domains_external_ipv6.txt"
        "zone_transfer.txt"
        "infra_as.txt"
        "infra_ipv4.txt"
        "infra_ipv4_diff.txt"
        "infra_ipv6.txt"
        "infra_blocks.txt"
        "webapp_consolidated.txt"
        "webapp_consolidated_diff.txt"
        "etc_hosts_file.txt"
        "vhost_subdomains_diff.txt"
        "email_recon.txt"
        "email_recon_diff.txt"
        "robots_urls.txt"
        "sitemap_urls.txt"
        "webapp_js_secrets.txt"
        "webapp_js_params.txt"
        "scan/nmap/nmap_scan.txt"
        "scan/nuclei/nuclei_scan.result"
        "scan/nuclei/nuclei_scan_diff.txt"
        "scan/nuclei/nuclei_web_fuzzing.result"
        "scan/shodan/shodan_scan.txt"
    )

    : > "${out}"
    sed \
        -e "s|__TARGET__|${target}|g" \
        -e "s|__TS__|${ts}|g" \
        -e "s|__REPORT_DIR__|${report_dir}|g" \
        "${header_file}" >> "${out}"
    echo >> "${out}"
    {
        echo "===== INDEX ====="
        for rel in "${artifacts[@]}"; do
            f="${report_dir}/${rel}"
            if [[ -s "${f}" ]]; then
                lines=$(wc -l < "${f}" 2>/dev/null | tr -d ' ')
                size=$(wc -c < "${f}" 2>/dev/null | tr -d ' ')
                printf '  [present] %-44s lines=%s size=%s\n' "${rel}" "${lines}" "${size}"
            else
                printf '  [empty]   %s\n' "${rel}"
            fi
        done
        echo "===== END INDEX ====="
        echo
    } >> "${out}"
    for rel in "${artifacts[@]}"; do
        llm_emit_artifact "${out}" "${report_dir}" "${rel}"
    done
    {
        echo "===== END OF BUNDLE ====="
        echo "# Total artifacts included : $(grep -c '^===== BEGIN ' "${out}")"
        echo "# Bundle size              : $(wc -c < "${out}" | tr -d ' ') bytes"
    } >> "${out}"
    echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} LLM prompt written → ${out}"
}
