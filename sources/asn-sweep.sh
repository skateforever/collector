#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * asn_sweep                                             #
#                                                           #
#############################################################
#
# PTR-sweeps the ASN/netblocks behind every discovered infrastructure IP
# (infra_ipv4.txt) — not just the root domain's own IP. Call explicitly
# from domains_recon.sh after infra_data() populates infra_ipv4.txt:
#   asn_sweep "${report_dir}/infra_ipv4.txt"
#
#############################################################

asn_sweep(){
    local asn_ip_file="$1"
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing ASN sweep... "
    : > "${tmp_dir}/asn_sweep_output.txt"

    if [[ ! -s "${asn_ip_file}" ]]; then
        echo "Done!"
        return 0
    fi

    # Cloud/CDN ASN org keywords — skip to avoid sweeping millions of unrelated IPs
    local asn_cloud_orgs="amazon|aws|google|microsoft|azure|cloudflare|fastly|akamai|limelight|level3|cogent"
    local asn_max_prefixes=5
    local asn_max_prefix_size=20  # only sweep blocks /20 or smaller (up to 4096 IPs)
    # Every discovered IP can land on a different ASN (subdomains split
    # across hosting providers) — cap how many distinct IPs we bother
    # resolving to an ASN at all, so a target with dozens of infra IPs
    # doesn't turn this into an hours-long sweep.
    local asn_max_targets=5
    local -A asn_seen_numbers
    local asn_target_ip asn_checked=0 asn_skipped=0
    local user_agent asn_bgp_page asn_number asn_org asn_prefixes_page
    local -a asn_prefixes

    while IFS= read -r asn_target_ip; do
        [[ -z "${asn_target_ip}" ]] && continue
        if [[ "${asn_checked}" -ge "${asn_max_targets}" ]]; then
            ((asn_skipped += 1))
            continue
        fi
        ((asn_checked += 1))

        # Step 1: IP → ASN via bgp.he.net
        unset user_agent
        user_agent="$(get_user_agent)"
        echo -e "\ncurl ${curl_options[@]} -H \"User-agent: ${user_agent}\" \"https://bgp.he.net/ip/${asn_target_ip}\"" >> "${log_execution_file}"
        # tr -d '\n': bgp.he.net's response has real newlines splitting the
        # markup unpredictably, and grep's `.` never matches across them —
        # normalizing to one line first makes every extraction below
        # reliable regardless of where the page happens to wrap.
        asn_bgp_page="$(curl "${curl_options[@]}" \
            -H "User-agent: ${user_agent}" \
            -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
            "https://bgp.he.net/ip/${asn_target_ip}" 2>> "${log_execution_file}" | tr -d '\n')"
        asn_number="$(echo "${asn_bgp_page}" | grep -Eo 'href="/AS[0-9]+"' | head -1 | grep -Eo '[0-9]+')"
        # The AS link's own text is just the AS number (<a href="/AS13335">AS13335</a>) —
        # the organization name lives in a separate, plain (no nested <a>/<span>)
        # <td> at the end of that same table row. Split on <tr> so each row is
        # its own line, find the one announcing this specific ASN, and pull the
        # last <td>...</td> immediately before that row's closing </tr>.
        asn_org="$(echo "${asn_bgp_page}" | sed 's/<tr>/\n<tr>/g' \
            | grep "href=\"/AS${asn_number}\"" | head -1 \
            | grep -oE '<td>[^<]*</td></tr>' \
            | sed -E 's/<td>([^<]*)<\/td>.*/\1/' \
            | tr '[:upper:]' '[:lower:]')"
        if [[ -z "${asn_number}" ]]; then
            echo -e "\nASN not found for ${asn_target_ip}" >> "${log_execution_file}"
            continue
        fi

        # Dedupe: multiple discovered IPs often share the same ASN — only
        # sweep each ASN once regardless of how many IPs pointed to it.
        if [[ -n "${asn_seen_numbers[${asn_number}]:-}" ]]; then
            echo -e "\nAS${asn_number} already swept (via a different IP) — skipping ${asn_target_ip}" >> "${log_execution_file}"
            continue
        fi
        asn_seen_numbers[${asn_number}]=1

        # Step 2: Filter cloud/CDN ASNs
        if echo "${asn_org}" | grep -qiE "${asn_cloud_orgs}"; then
            echo -e "\nAS${asn_number} (${asn_org}) is a cloud provider — skipping ASN sweep" >> "${log_execution_file}"
            continue
        fi
        echo -e "\n${asn_target_ip} → AS${asn_number} (${asn_org})" >> "${log_execution_file}"

        # Step 3: ASN → prefix list via bgp.he.net
        echo -e "\ncurl ${curl_options[@]} -H \"User-agent: ${user_agent}\" \"https://bgp.he.net/AS${asn_number}\"" >> "${log_execution_file}"
        asn_prefixes_page="$(curl "${curl_options[@]}" \
            -H "User-agent: ${user_agent}" \
            -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
            "https://bgp.he.net/AS${asn_number}" 2>> "${log_execution_file}" | tr -d '\n')"
        asn_prefixes=()
        while IFS= read -r asn_prefix; do
            [[ -z "${asn_prefix}" ]] && continue
            asn_prefix_size="${asn_prefix##*/}"
            if [[ "${asn_prefix_size}" -ge "${asn_max_prefix_size}" ]]; then
                asn_prefixes+=("${asn_prefix}")
            fi
            [[ ${#asn_prefixes[@]} -ge "${asn_max_prefixes}" ]] && break
        done < <(echo "${asn_prefixes_page}" | grep -Eo 'href="/net/[0-9.]+/[0-9]+"' | grep -Eo '[0-9.]+/[0-9]+' | sort -u)
        if [[ ${#asn_prefixes[@]} -eq 0 ]]; then
            echo -e "\nNo sweepable prefixes found for AS${asn_number}" >> "${log_execution_file}"
            continue
        fi
        echo -e "\nAS${asn_number}: ${#asn_prefixes[@]} prefix(es) to sweep: ${asn_prefixes[*]}" >> "${log_execution_file}"

        # Step 4: PTR sweep across all prefixes for this ASN.
        # Enumerate every host address in the CIDR, not just the first /24.
        for asn_cidr in "${asn_prefixes[@]}"; do
            echo -e "\nPTR sweep for ${asn_cidr}" >> "${log_execution_file}"
            asn_base_ip="${asn_cidr%%/*}"
            asn_prefix_len="${asn_cidr##*/}"
            asn_host_bits=$(( 32 - asn_prefix_len ))
            asn_total_ips=$(( 1 << asn_host_bits ))
            IFS='.' read -r asn_o1 asn_o2 asn_o3 asn_o4 <<< "${asn_base_ip}"
            asn_ip_int=$(( (asn_o1 << 24) | (asn_o2 << 16) | (asn_o3 << 8) | asn_o4 ))
            for (( asn_i=1; asn_i < asn_total_ips - 1; asn_i++ )); do
                asn_cur=$(( asn_ip_int + asn_i ))
                asn_a=$(( (asn_cur >> 24) & 255 ))
                asn_b=$(( (asn_cur >> 16) & 255 ))
                asn_c=$(( (asn_cur >>  8) & 255 ))
                asn_d=$(( asn_cur & 255 ))
                asn_ptr="$(dig +short -x "${asn_a}.${asn_b}.${asn_c}.${asn_d}" 2>/dev/null | sed 's/\.$//' | tr '[:upper:]' '[:lower:]')"
                [[ -n "${asn_ptr}" ]] && echo "${asn_ptr}" >> "${tmp_dir}/asn_sweep_output.txt"
            done
        done
    done < <(sort -u "${asn_ip_file}")

    if [[ "${asn_skipped}" -gt 0 ]]; then
        echo "asn-sweep: skipped ${asn_skipped} additional IP(s) beyond the ${asn_max_targets}-target cap" >> "${log_execution_file}"
    fi

    sort -u -o "${tmp_dir}/asn_sweep_output.txt" "${tmp_dir}/asn_sweep_output.txt" 2>/dev/null
    echo "Done!"
}
