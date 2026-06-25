#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * asn-sweep-src                                         #
#                                                           #
#############################################################

asn-sweep-src(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing ASN sweep... "
    : > "${tmp_dir}/asn_sweep_output.txt"
    # Cloud/CDN ASN org keywords — skip to avoid sweeping millions of unrelated IPs
    asn_cloud_orgs="amazon|aws|google|microsoft|azure|cloudflare|fastly|akamai|limelight|level3|cogent"
    asn_max_prefixes=5
    asn_max_prefix_size=20  # only sweep blocks /20 or smaller (up to 4096 IPs)
    asn_target_ip="$(dig +short A "${domain}" 2>/dev/null | grep -Eo "${IPv4_regex}" | head -1)"
    if [[ -z "${asn_target_ip}" ]]; then
        echo "Done!"
        return 0
    fi
    # Step 1: IP → ASN via bgp.he.net
    unset user_agent
    user_agent="$(get_user_agent)"
    echo -e "\ncurl ${curl_options[@]} -H \"User-agent: ${user_agent}\" \"https://bgp.he.net/ip/${asn_target_ip}\"" >> "${log_execution_file}"
    asn_bgp_page="$(curl "${curl_options[@]}" \
        -H "User-agent: ${user_agent}" \
        -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
        "https://bgp.he.net/ip/${asn_target_ip}" 2>> "${log_execution_file}")"
    asn_number="$(echo "${asn_bgp_page}" | grep -Eo 'href="/AS[0-9]+"' | head -1 | grep -Eo '[0-9]+')"
    asn_org="$(echo "${asn_bgp_page}" | grep -Eo 'href="/AS[0-9]+">[^<]+' | head -1 | sed 's/.*>//' | tr '[:upper:]' '[:lower:]')"
    if [[ -z "${asn_number}" ]]; then
        echo -e "\nASN not found for ${asn_target_ip}" >> "${log_execution_file}"
        echo "Done!"
        return 0
    fi
    # Step 2: Filter cloud/CDN ASNs
    if echo "${asn_org}" | grep -qiE "${asn_cloud_orgs}"; then
        echo -e "\nAS${asn_number} (${asn_org}) is a cloud provider — skipping ASN sweep" >> "${log_execution_file}"
        echo "Done!"
        return 0
    fi
    echo -e "\n${asn_target_ip} → AS${asn_number} (${asn_org})" >> "${log_execution_file}"
    # Step 3: ASN → prefix list via bgp.he.net
    echo -e "\ncurl ${curl_options[@]} -H \"User-agent: ${user_agent}\" \"https://bgp.he.net/AS${asn_number}\"" >> "${log_execution_file}"
    asn_prefixes_page="$(curl "${curl_options[@]}" \
        -H "User-agent: ${user_agent}" \
        -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
        "https://bgp.he.net/AS${asn_number}" 2>> "${log_execution_file}")"
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
        echo "Done!"
        return 0
    fi
    echo -e "\nAS${asn_number}: ${#asn_prefixes[@]} prefix(es) to sweep: ${asn_prefixes[*]}" >> "${log_execution_file}"
    # Step 4: PTR sweep across all prefixes
    for asn_cidr in "${asn_prefixes[@]}"; do
        asn_base="$(echo "${asn_cidr}" | cut -d'/' -f1 | awk -F'.' '{print $1"."$2"."$3}')"
        echo -e "\nPTR sweep for ${asn_cidr}" >> "${log_execution_file}"
        for asn_last in $(seq 1 254); do
            asn_ptr="$(dig +short -x "${asn_base}.${asn_last}" 2>/dev/null | sed 's/\.$//' | tr '[:upper:]' '[:lower:]')"
            if [[ -n "${asn_ptr}" ]]; then
                echo "${asn_ptr}" >> "${tmp_dir}/asn_sweep_output.txt"
            fi
        done
    done
    sort -u -o "${tmp_dir}/asn_sweep_output.txt" "${tmp_dir}/asn_sweep_output.txt" 2>/dev/null
    echo "Done!"
}

asn-sweep-src
