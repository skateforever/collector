#!/bin/bash
#############################################################
# The main file to handle all results from sources          #
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * joining_subdomains                                    #
#   * organizing_subdomains                                 #
#                                                           #
#############################################################            

joining_subdomains(){
    echo -en "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Putting all domain search results in one file... "
    if [ -d "${tmp_dir}" ] && [ -d "${report_dir}" ]; then
        if [ -s "${tmp_dir}/alienvault_output.json" ]; then
            echo "Parsing alivenvault" >> "${log_execution_file}"
            jq -r '.passive_dns[]?.hostname' "${tmp_dir}/alienvault_output.json" \
                | sort -u >> "${tmp_dir}/domains_found.tmp" 2>> "${log_execution_file}"
        fi

        if [ -s "${tmp_dir}/anubis_output.json" ]; then
            echo "Parsing anubis" >> "${log_execution_file}"
            jq -r '.[]' "${tmp_dir}/anubis_output.json" \
                | sort -u >> "${tmp_dir}/domains_found.tmp" 2>> "${log_execution_file}"
        fi

        if [ -s "${tmp_dir}/amass_output.tmp" ]; then
            echo "Parsing amass search" >> "${log_execution_file}"
            # Na v5 a saída já vem limpa, apenas filtramos pelo domínio correto
            grep -E "^.*\.${domain}" "${tmp_dir}/amass_output.tmp" \
                | sort -u >> "${tmp_dir}/domains_found.tmp" 2>> "${log_execution_file}"
        fi

        if [ -s "${tmp_dir}/builtwith_subdomain_output.json" ]; then
            echo "Parsing builtwith" >> "${log_execution_file}"
            for subdomain in $(jq -r '.Results[].Result.Paths[].SubDomain' "${tmp_dir}/builtwith_subdomain_output.json"); do
                [[ "${subdomain}" != "${domain}" ]] && echo "${subdomain}" | sed "s/$/\.${domain}/"
            done | sort -u >> "${tmp_dir}/domains_found.tmp" 2>> "${log_execution_file}"
        fi

        if [ -s "${tmp_dir}/certspotter_output.json" ]; then
            echo "Parsing cert spotter" >> "${log_execution_file}"
            jq -r '.[].dns_names[]' "${tmp_dir}/certspotter_output.json" \
                | sed 's/\"//g' \
                | sed 's/\*\.//g' \
                | sort -u \
                | grep "${domain}" >> "${tmp_dir}/domains_found.tmp" 2>> "${log_execution_file}"
        fi

        if [ -s "${tmp_dir}/commoncrawl_output.json" ]; then
            echo "Parsing common crawl" >> "${log_execution_file}"
            jq -r '.url?' "${tmp_dir}/commoncrawl_output.json" \
                | sed 's/\*\.//g' \
                | sed -e 's_https*://__' -e "s/\/.*//" -e 's/:.*//' -e "/@/d" -e 's/\.$//' \
                | sort -u >> "${tmp_dir}/domains_found.tmp" 2>> "${log_execution_file}"
        fi

        if [ -s "${tmp_dir}/crtsh_output.json" ]; then
            echo "Parsing crt sh" >> "${log_execution_file}"
            jq -r '.[].name_value' "${tmp_dir}/crtsh_output.json" \
                | sed 's/\*\.//g' \
                | sort -u >> "${tmp_dir}/domains_found.tmp" 2>> "${log_execution_file}"
        fi
        
        if [ -s "${tmp_dir}/dnsdumpster_output.json" ]; then
            echo "Parsing dns dumpster" >> "${log_execution_file}"
            jq -r '.a[].host' "${tmp_dir}/dnsdumpster_output.json" \
                | sed 's/^\*\.//' \
                | sort -u >> "${tmp_dir}/domains_found.tmp" 2>> "${log_execution_file}"
        fi

        if [ -s "${tmp_dir}/dnsrepo_output.html" ]; then
            echo "Parsing dnsrepo" >> "${log_execution_file}"
            grep -Ei "domain=.*\.${domain}" "${tmp_dir}/dnsrepo_output.html" \
                | sed 's/\.<.*//g ; s/.*<.*>//g' \
                | sort -u >> "${tmp_dir}/domains_found.tmp" 2>> "${log_execution_file}"
        fi

        if [ -s "${tmp_dir}/hackertarget_output.txt" ]; then
            echo "Parsing hackertarget" >> "${log_execution_file}"
            grep -v "API count exceeded - Increase Quota with Membership" "${tmp_dir}/hackertarget_output.txt" \
                | awk -F',' '{print $1}' \
                | sed 's/^\*\.//' \
                | sort -u >> "${tmp_dir}/domains_found.tmp" 2>> "${log_execution_file}"
        fi

        if [ -s "${tmp_dir}/katana_output.tmp" ]; then
            echo "Parsing katana" >> "${log_execution_file}"
            awk -F'/' '{print $3}' "${tmp_dir}/katana_output.tmp" \
                | sort -u >> "${tmp_dir}/domains_found.tmp" 2>> "${log_execution_file}"
        fi

        if [ -s "${tmp_dir}/netlas_output.json" ]; then
            echo "Parsing  netlas" >> "${log_execution_file}"
            jq -r '.items[].data.domain' "${tmp_dir}/netlas_output.json" \
                | sort -u >> "${tmp_dir}/domains_found.tmp" 2>> "${log_execution_file}"
        fi

        if [ -s "${tmp_dir}/netcraft_output.txt" ]; then
            echo "Parsing netcraft" >> "${log_execution_file}"
            grep -Ei "(\.${domain}$|^${domain}$)" "${tmp_dir}/netcraft_output.txt" \
                | sort -u >> "${tmp_dir}/domains_found.tmp" 2>> "${log_execution_file}"
        fi

        if [ -s "${tmp_dir}/rapiddns_output.txt" ]; then
            echo "Parsing rapiddns" >> "${log_execution_file}"
            grep -Ei "<td>.*${domain}</td>" "${tmp_dir}/rapiddns_output.txt" \
                | sed 's/<td>// ; s/<\/td>//' \
                | sort -u >> "${tmp_dir}/domains_found.tmp" 2>> "${log_execution_file}"
        fi

        if [ -s "${tmp_dir}/robtex_output.json" ]; then
            echo "Parsing robtex" >> "${log_execution_file}"
            jq -r '.rrname' "${tmp_dir}/robtex_output.json" \
                | sort -u >> "${tmp_dir}/domains_found.tmp" 2>> "${log_execution_file}"
        fi

        if [ -s "${tmp_dir}/hackerone_output.json" ]; then
            echo "Parsing hackerone" >> "${log_execution_file}"
            jq -r '.data.team.structured_scopes.edges[].node.asset_identifier' \
                "${tmp_dir}/hackerone_output.json" 2>> "${log_execution_file}" \
                | grep -Ei "(\.${domain}$|^${domain}$)" \
                | sort -u >> "${tmp_dir}/domains_found.tmp"
        fi

        if [ -s "${tmp_dir}/securitytrails_output.json" ]; then
            echo "Parsing security trails" >> "${log_execution_file}"
            for subdomain in $(jq -r '.subdomains[]' "${tmp_dir}/securitytrails_output.json"); do
                [[ "${subdomain}" != "${domain}" ]] && echo "${subdomain}" | sed "s/$/\.${domain}/"
            done | sort -u >> "${tmp_dir}/domains_found.tmp" 2>> "${log_execution_file}"
        fi

        if [ -s "${tmp_dir}/shodan_output.txt" ]; then
            echo "Parsing shodan" >> "${log_execution_file}"
            sed -i -e 's/;/\n/g' -e '/^$/d' "${tmp_dir}/shodan_output.txt"
            sort -u "${tmp_dir}/shodan_output.txt" \
                | grep -E "^.*\.${domain}" >> "${tmp_dir}/domains_found.tmp" 2>> "${log_execution_file}"
        fi

        if [ -s "${tmp_dir}/subdomaincenter_output.json" ]; then
            echo "Parsing subdomain center" >> "${log_execution_file}"
            jq -r '.[]' "${tmp_dir}/subdomaincenter_output.json" 2>> "${log_execution_file}" \
                | sort -u >> "${tmp_dir}/domains_found.tmp"
        fi

        if [ -s "${tmp_dir}/subfinder_output.tmp" ]; then
            echo "Parsing subfinder" >> "${log_execution_file}"
            grep -E "^.*\.${domain}" "${tmp_dir}/subfinder_output.tmp" \
                >> "${tmp_dir}/domains_found.tmp" 2>> "${log_execution_file}"
        fi

        if [ -s "${tmp_dir}/sublist3r_output.tmp" ]; then
            echo "Parsing sublist3r" >> "${log_execution_file}"
            grep -E "^.*\.${domain}" "${tmp_dir}/sublist3r_output.tmp" \
                | sort -u >> "${tmp_dir}/domains_found.tmp" 2>> "${log_execution_file}"
        fi

        if [ -s "${tmp_dir}/tlsx_output.json" ]; then
            echo "Parsing tlsx" >> "${log_execution_file}"
            jq -r '.subject_an[]' "${tmp_dir}/tlsx_output.json" \
                | grep -E "^.*\.${domain}" >> "${tmp_dir}/domains_found.tmp" 2>> "${log_execution_file}"
        fi

        if [ -s "${tmp_dir}/urlfinder_output.tmp" ]; then
            echo "Parsing urlfinder" >> "${log_execution_file}"
            awk -F'/' '{print $3}' "${tmp_dir}/urlfinder_output.tmp" \
                | sort -u >> "${tmp_dir}/domains_found.tmp" 2>> "${log_execution_file}"
        fi

        if [ -s "${tmp_dir}/urlscan_output.json" ]; then
            echo "Parsing urlscan" >> "${log_execution_file}"
            jq -r '.results[].task.domain' "${tmp_dir}/urlscan_output.json" \
                | sort -u >> "${tmp_dir}/domains_found.tmp" 2>> "${log_execution_file}"
        fi

        if [ -s "${tmp_dir}/virustotal_output.json" ]; then
            echo "Parsing virus total" >> "${log_execution_file}"
            jq -r '.data[]?.id' "${tmp_dir}/virustotal_output.json" \
                | sort -u >> "${tmp_dir}/domains_found.tmp" 2>> "${log_execution_file}"
        fi

        if [ -s "${tmp_dir}/waybackurls_output.tmp" ]; then
            echo "Parsing waybackurls" >> "${log_execution_file}"
            awk -F'/' '{print $3}' "${tmp_dir}/waybackurls_output.tmp" \
                | awk -F'?' '{print $1}' \
                | sed 's/:[0-9]*$//g' \
                | sort -u >> "${tmp_dir}/domains_found.tmp" 2>> "${log_execution_file}"
        fi

        if [ -s "${tmp_dir}/webarchive_output.txt" ]; then
            echo "Parsing webarchive" >> "${log_execution_file}"
            cat "${tmp_dir}/webarchive_output.txt" \
                | sed -e 's_https*://__' -e "s/\/.*//" -e 's/:.*//' -e 's/^www\.//' \
                | sed "/@/d" \
                | sed -e 's/\.$//' \
                | sed 's/:[0-9]*$//g' \
                | sort -u >> "${tmp_dir}/domains_found.tmp" 2>> "${log_execution_file}"
        fi

        if [ -s "${tmp_dir}/whoisxmlapi_output.json" ]; then
           echo "Parsing whoisxmlapi" >> "${log_execution_file}"
           jq -r '.domainsList[]' "${tmp_dir}/whoisxmlapi_output.json" \
                | sort -u \
                | grep -E "^.*\.${domain}" 2> /dev/null >> "${tmp_dir}/domains_found.tmp" \
                2>> "${log_execution_file}"
        fi

        if [ -s "${tmp_dir}/bufferover_output.json" ]; then
            echo "Parsing bufferover" >> "${log_execution_file}"
            jq -r '(.FDNS_A // [])[], (.RDNS // [])[]' "${tmp_dir}/bufferover_output.json" 2>> "${log_execution_file}" \
                | awk -F',' '{for(i=1;i<=NF;i++) if ($i !~ /^[0-9.]+$/) print $i}' \
                | sort -u >> "${tmp_dir}/domains_found.tmp" 2>> "${log_execution_file}"
        fi

        if [ -s "${tmp_dir}/jldc_output.json" ]; then
            echo "Parsing jldc" >> "${log_execution_file}"
            jq -r '.[]' "${tmp_dir}/jldc_output.json" 2>> "${log_execution_file}" \
                | sort -u >> "${tmp_dir}/domains_found.tmp" 2>> "${log_execution_file}"
        fi

        if [ -s "${tmp_dir}/circl_output.txt" ]; then
            echo "Parsing circl" >> "${log_execution_file}"
            grep -Eo '"rrname"[[:space:]]*:[[:space:]]*"[^"]+"' "${tmp_dir}/circl_output.txt" \
                | awk -F'"' '{print $4}' \
                | sed 's/\.$//' \
                | sort -u >> "${tmp_dir}/domains_found.tmp" 2>> "${log_execution_file}"
        fi

        if [ -s "${tmp_dir}/threatminer_output.json" ]; then
            echo "Parsing threatminer" >> "${log_execution_file}"
            jq -r '.results[]?' "${tmp_dir}/threatminer_output.json" 2>> "${log_execution_file}" \
                | sort -u >> "${tmp_dir}/domains_found.tmp" 2>> "${log_execution_file}"
        fi

        if [ -s "${tmp_dir}/urlhaus_output.json" ]; then
            echo "Parsing urlhaus" >> "${log_execution_file}"
            jq -r '.urls[]?.url?' "${tmp_dir}/urlhaus_output.json" 2>> "${log_execution_file}" \
                | sed -e 's_https*://__' -e 's_/.*__' -e 's_:.*__' \
                | sort -u >> "${tmp_dir}/domains_found.tmp" 2>> "${log_execution_file}"
        fi

        if [ -s "${tmp_dir}/bing_output.txt" ]; then
            echo "Parsing bing" >> "${log_execution_file}"
            grep -Eo 'hover-url="https?://[^"]+"|<cite[^>]*>[^<]+</cite>|href="https?://(?!(?:www\.)?bing\.com)[^"]+"' "${tmp_dir}/bing_output.txt" \
                | grep -Eo 'https?://[^/" >]+' \
                | sed -e 's_https*://__' -e 's_/.*__' -e 's_:.*__' -e 's/^www\.//' \
                | grep -E "\.${domain}$" \
                | sort -u >> "${tmp_dir}/domains_found.tmp" 2>> "${log_execution_file}"
        fi

        if [ -s "${tmp_dir}/grepapp_output.json" ]; then
            echo "Parsing grepapp" >> "${log_execution_file}"
            grep -Eo '[a-zA-Z0-9._-]+\.'"${domain}" "${tmp_dir}/grepapp_output.json" \
                | tr '[:upper:]' '[:lower:]' \
                | sort -u >> "${tmp_dir}/domains_found.tmp" 2>> "${log_execution_file}"
        fi

        if [ -s "${tmp_dir}/bevigil_output.json" ]; then
            echo "Parsing bevigil" >> "${log_execution_file}"
            jq -r '.subdomains[]?' "${tmp_dir}/bevigil_output.json" \
                | tr '[:upper:]' '[:lower:]' \
                | sort -u >> "${tmp_dir}/domains_found.tmp" 2>> "${log_execution_file}"
        fi

        if [ -s "${tmp_dir}/c99_output.json" ]; then
            echo "Parsing c99" >> "${log_execution_file}"
            jq -r '.subdomains[]? | if type == "string" then . else (.subdomain // .host // .hostname // empty) end' \
                "${tmp_dir}/c99_output.json" \
                | tr '[:upper:]' '[:lower:]' \
                | sort -u >> "${tmp_dir}/domains_found.tmp" 2>> "${log_execution_file}"
        fi

        if [ -s "${tmp_dir}/chaos_output.json" ]; then
            echo "Parsing chaos" >> "${log_execution_file}"
            chaos_root="$(jq -r '.domain // empty' "${tmp_dir}/chaos_output.json" 2>/dev/null)"
            [[ -z "${chaos_root}" ]] && chaos_root="${domain}"
            jq -r '.subdomains[]?' "${tmp_dir}/chaos_output.json" \
                | tr '[:upper:]' '[:lower:]' \
                | sed "s/\$/.${chaos_root}/" \
                | sort -u >> "${tmp_dir}/domains_found.tmp" 2>> "${log_execution_file}"
        fi

        if [ -s "${tmp_dir}/fofa_output.json" ]; then
            echo "Parsing fofa" >> "${log_execution_file}"
            jq -r '.results[]? | if type == "array" then .[] else . end' "${tmp_dir}/fofa_output.json" \
                | grep -Eo '[a-zA-Z0-9._-]+\.'"${domain}" \
                | tr '[:upper:]' '[:lower:]' \
                | sort -u >> "${tmp_dir}/domains_found.tmp" 2>> "${log_execution_file}"
        fi

        if [ -s "${tmp_dir}/fofa_output.html" ]; then
            echo "Parsing fofa html" >> "${log_execution_file}"
            grep -Eo '[a-zA-Z0-9._-]+\.'"${domain}" "${tmp_dir}/fofa_output.html" \
                | tr '[:upper:]' '[:lower:]' \
                | sort -u >> "${tmp_dir}/domains_found.tmp" 2>> "${log_execution_file}"
        fi

        if [ -s "${tmp_dir}/fullhunt_output.json" ]; then
            echo "Parsing fullhunt" >> "${log_execution_file}"
            jq -r '.hosts[]? | if type == "string" then . else (.host // empty) end' \
                "${tmp_dir}/fullhunt_output.json" \
                | tr '[:upper:]' '[:lower:]' \
                | sort -u >> "${tmp_dir}/domains_found.tmp" 2>> "${log_execution_file}"
        fi

        if [ -s "${tmp_dir}/github_output.json" ]; then
            echo "Parsing github" >> "${log_execution_file}"
            grep -Eo '[a-zA-Z0-9._-]+\.'"${domain}" "${tmp_dir}/github_output.json" \
                | tr '[:upper:]' '[:lower:]' \
                | sort -u >> "${tmp_dir}/domains_found.tmp" 2>> "${log_execution_file}"
        fi

        if [ -s "${tmp_dir}/grayhatwarfare_output.json" ]; then
            echo "Parsing grayhatwarfare" >> "${log_execution_file}"
            jq -r '.buckets[]?.bucket // empty' "${tmp_dir}/grayhatwarfare_output.json" \
                | grep -Eo '[a-zA-Z0-9._-]+\.'"${domain}" \
                | tr '[:upper:]' '[:lower:]' \
                | sort -u >> "${tmp_dir}/domains_found.tmp" 2>> "${log_execution_file}"
        fi

        if [ -s "${tmp_dir}/greynoise_output.json" ]; then
            echo "Parsing greynoise" >> "${log_execution_file}"
            jq -r '.data[]?.metadata?.rdns // empty' "${tmp_dir}/greynoise_output.json" \
                | sed 's/\.$//' \
                | tr '[:upper:]' '[:lower:]' \
                | grep -E "\.${domain}$" \
                | sort -u >> "${tmp_dir}/domains_found.tmp" 2>> "${log_execution_file}"
        fi

        if [ -s "${tmp_dir}/hunterhow_output.json" ]; then
            echo "Parsing hunterhow" >> "${log_execution_file}"
            jq -r '.data?.assets[]?.domain // empty' "${tmp_dir}/hunterhow_output.json" \
                | tr '[:upper:]' '[:lower:]' \
                | sort -u >> "${tmp_dir}/domains_found.tmp" 2>> "${log_execution_file}"
        fi

        if [ -s "${tmp_dir}/intelx_output.json" ]; then
            echo "Parsing intelx" >> "${log_execution_file}"
            jq -r '.selectors[]?.selectorvalue // empty' "${tmp_dir}/intelx_output.json" \
                | grep -Eo '[a-zA-Z0-9._-]+\.'"${domain}" \
                | tr '[:upper:]' '[:lower:]' \
                | sort -u >> "${tmp_dir}/domains_found.tmp" 2>> "${log_execution_file}"
        fi

        if [ -s "${tmp_dir}/leakix_output.json" ]; then
            echo "Parsing leakix" >> "${log_execution_file}"
            jq -r 'if type == "array" then .[]? | if type == "string" then . else (.subdomain // .host // .hostname // empty) end else empty end' \
                "${tmp_dir}/leakix_output.json" \
                | tr '[:upper:]' '[:lower:]' \
                | sort -u >> "${tmp_dir}/domains_found.tmp" 2>> "${log_execution_file}"
        fi

        if [ -s "${tmp_dir}/merklemap_output.json" ]; then
            echo "Parsing merklemap" >> "${log_execution_file}"
            jq -r '.results[]? | if type == "string" then . else (.domain // .hostname // .name // .subdomain // empty) end' \
                "${tmp_dir}/merklemap_output.json" \
                | tr '[:upper:]' '[:lower:]' \
                | sort -u >> "${tmp_dir}/domains_found.tmp" 2>> "${log_execution_file}"
        fi

        if [ -s "${tmp_dir}/onyphe_output.json" ]; then
            echo "Parsing onyphe" >> "${log_execution_file}"
            jq -r '.results[]? | (.hostname // .domain // .forward // empty)' "${tmp_dir}/onyphe_output.json" \
                | tr '[:upper:]' '[:lower:]' \
                | grep -E "\.${domain}$" \
                | sort -u >> "${tmp_dir}/domains_found.tmp" 2>> "${log_execution_file}"
        fi

        if [ -s "${tmp_dir}/publicwww_output.txt" ]; then
            echo "Parsing publicwww" >> "${log_execution_file}"
            grep -Eo '[a-zA-Z0-9._-]+\.'"${domain}" "${tmp_dir}/publicwww_output.txt" \
                | tr '[:upper:]' '[:lower:]' \
                | sort -u >> "${tmp_dir}/domains_found.tmp" 2>> "${log_execution_file}"
        fi

        if [ -s "${tmp_dir}/pulsedive_output.json" ]; then
            echo "Parsing pulsedive" >> "${log_execution_file}"
            jq -r '(.indicators // .results // [])[]? | select(.type == "domain") | (.value // .indicator // empty)' \
                "${tmp_dir}/pulsedive_output.json" \
                | tr '[:upper:]' '[:lower:]' \
                | sort -u >> "${tmp_dir}/domains_found.tmp" 2>> "${log_execution_file}"
        fi

        if [ -s "${tmp_dir}/ptr_sweep_output.txt" ]; then
            echo "Parsing ptr_sweep" >> "${log_execution_file}"
            grep -Ei "(\.${domain}$|^${domain}$)" "${tmp_dir}/ptr_sweep_output.txt" \
                | sort -u >> "${tmp_dir}/domains_found.tmp" 2>> "${log_execution_file}"
        fi

        if [ -s "${tmp_dir}/dns_mining_output.txt" ]; then
            echo "Parsing dns_mining" >> "${log_execution_file}"
            grep -Ei "(\.${domain}$|^${domain}$)" "${tmp_dir}/dns_mining_output.txt" \
                | sort -u >> "${tmp_dir}/domains_found.tmp" 2>> "${log_execution_file}"
        fi

        if [ -s "${tmp_dir}/caa_enum_output.txt" ]; then
            echo "Parsing caa_enum" >> "${log_execution_file}"
            grep -Ei "(\.${domain}$|^${domain}$)" "${tmp_dir}/caa_enum_output.txt" \
                | sort -u >> "${tmp_dir}/domains_found.tmp" 2>> "${log_execution_file}"
        fi

        if [ -s "${tmp_dir}/srv_enum_output.txt" ]; then
            echo "Parsing srv_enum" >> "${log_execution_file}"
            grep -Ei "(\.${domain}$|^${domain}$)" "${tmp_dir}/srv_enum_output.txt" \
                | sort -u >> "${tmp_dir}/domains_found.tmp" 2>> "${log_execution_file}"
        fi

        if [ -s "${tmp_dir}/nsec_walk_output.txt" ]; then
            echo "Parsing nsec_walk" >> "${log_execution_file}"
            grep -Ei "(\.${domain}$|^${domain}$)" "${tmp_dir}/nsec_walk_output.txt" \
                | sort -u >> "${tmp_dir}/domains_found.tmp" 2>> "${log_execution_file}"
        fi

        if [ -s "${tmp_dir}/ns_brute_output.txt" ]; then
            echo "Parsing ns_brute" >> "${log_execution_file}"
            awk '/IN[[:space:]]+A[[:space:]]/{print $1}' "${tmp_dir}/ns_brute_output.txt" \
                | sed 's/\.$//' | tr '[:upper:]' '[:lower:]' \
                | grep -Ei "(\.${domain}$|^${domain}$)" \
                | sort -u >> "${tmp_dir}/domains_found.tmp" 2>> "${log_execution_file}"
        fi

        if [ -s "${tmp_dir}/asn_sweep_output.txt" ]; then
            echo "Parsing asn_sweep" >> "${log_execution_file}"
            grep -Ei "(\.${domain}$|^${domain}$)" "${tmp_dir}/asn_sweep_output.txt" \
                | sort -u >> "${tmp_dir}/domains_found.tmp" 2>> "${log_execution_file}"
        fi

        if [ -s "${tmp_dir}/censys_output.json" ]; then
            echo "Parsing censys" >> "${log_execution_file}"
            jq -r '.result.hits[]?.parsed?.names[]?' "${tmp_dir}/censys_output.json" \
                | tr '[:upper:]' '[:lower:]' \
                | sort -u >> "${tmp_dir}/domains_found.tmp" 2>> "${log_execution_file}"
        fi

        if [ -s "${tmp_dir}/robots_sitemap_output.txt" ]; then
            echo "Parsing robots_sitemap" >> "${log_execution_file}"
            grep -Ei "(\.${domain}$|^${domain}$)" "${tmp_dir}/robots_sitemap_output.txt" \
                | sort -u >> "${tmp_dir}/domains_found.tmp" 2>> "${log_execution_file}"
        fi

        if [ -s "${tmp_dir}/spider_output.txt" ]; then
            echo "Parsing spider" >> "${log_execution_file}"
            grep -Ei "(\.${domain}$|^${domain}$)" "${tmp_dir}/spider_output.txt" \
                | sort -u >> "${tmp_dir}/domains_found.tmp" 2>> "${log_execution_file}"
        fi

        if [ -s "${tmp_dir}/vhost_probe_output.txt" ]; then
            echo "Parsing vhost_probe" >> "${log_execution_file}"
            grep -Ei "(\.${domain}$|^${domain}$)" "${tmp_dir}/vhost_probe_output.txt" \
                | sort -u >> "${tmp_dir}/domains_found.tmp" 2>> "${log_execution_file}"
        fi

        if [ ${#dns_wordlists[@]} -gt 0 ]; then
            echo "Parsing amass brute" >> "${log_execution_file}"
            files_amass=($("${ls_bin_path}" -1A "${tmp_dir}/" | grep "amass_brute_output" 2> /dev/null))
            for f in "${files_amass[@]}"; do
                file="${tmp_dir}"/"${f}"
                if [[ -s "${file}" ]]; then
                    # Ajustado para ler a saída limpa do Amass v5
                    grep -E "^.*\.${domain}" "${file}" \
                        | sort -u >> "${tmp_dir}/domains_found.tmp" \
                        2>> "${log_execution_file}"
                fi
                unset file
            done

            echo "Parsing gobuster brute" >> "${log_execution_file}"
            files_gobuster_dns=($("${ls_bin_path}" -1A "${tmp_dir}/" | grep "gobuster_dns_output" 2> /dev/null))
            for f in "${files_gobuster_dns[@]}"; do
                file="${tmp_dir}"/"${f}"
                if [[ -s "${file}" ]]; then
                    awk '{print $2}' "${file}" \
                        | tr '[:upper:]' '[:lower:]' \
                        | grep -E "^.*\.${domain}" \
                        | sort -u >> "${tmp_dir}/domains_found.tmp" \
                        2>> "${log_execution_file}"
                fi
                unset file
            done

            echo "Parsing dnssearch" >> "${log_execution_file}"
            files_dnssearch=($("${ls_bin_path}" -1A "${tmp_dir}/" | grep "dnssearch_output_" 2> /dev/null))
            for f in "${files_dnssearch[@]}"; do
                file="${tmp_dir}"/"${f}"
                if [[ -s "${file}" ]]; then
                    awk '{print $1}' "${file}" \
                        | tr '[:upper:]' '[:lower:]' \
                        | grep -E "^.*\.${domain}" \
                        | sort -u >> "${tmp_dir}/domains_found.tmp" \
                        2>> "${log_execution_file}"
                fi
                unset file
            done
        fi

        if [ -s "${tmp_dir}/domains_found.tmp" ]; then
            echo "Done!"
            echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Joining the subdomains and removing duplicates... "
            # Removing duplicated subdomains
            cp "${tmp_dir}/domains_found.tmp" "${tmp_dir}/domains_found.tmp.old"
            sed -E -i 's/^null$//g ; s/^\*//g ; s/^@//g ; s/^\.//g ; s/\.$//g ; s/^-//g ; s/^\://g' "${tmp_dir}/domains_found.tmp"
            sed -E -i 's/\.\./\./g ; s/^http(|s):\/\///g ; s/ //g ; s/^$//g ; /^[[:space:]]*$/d' "${tmp_dir}/domains_found.tmp"
            # Removing duplicated domains per subdomain
            # Example: www.domain.com.domain.com
            while grep -qE "${domain}\.${domain}$" "${tmp_dir}/domains_found.tmp"; do
                sed -i "s/${domain}\.${domain}$/${domain}/" "${tmp_dir}/domains_found.tmp"
            done

            if tr '[:upper:]' '[:lower:]' < "${tmp_dir}/domains_found.tmp" \
                | grep -vE "@" \
                | sort -u > "${report_dir}/domains_found.txt" ; then
                sed -i '/owasp.*nonce/d ; /_/d ; /\*/d ; /^[[:blank:]]/d ; /</d ; />/d' "${report_dir}/domains_found.txt"
                echo "Done!"
            fi

            if [ ${#excluded_domains[@]} -gt 0 ] && [ -s "${report_dir}/domains_found.txt" ]; then
                echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Excluding the subdomains from command line option... "
                for subdomain in "${excluded_domains[@]}"; do
                    sed -i "/^${subdomain}$/d" "${report_dir}/domains_found.txt"
                done
                unset subdomain
                # Fixing blank lines after excluding domains
                sed -i '/^$/d' "${report_dir}/domains_found.txt"
                echo "Done!"
            fi

            if [ -s "${excludedomain_list}" ] && [ -s "${report_dir}/domains_found.txt" ]; then
                echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Excluding the subdomains from file list option... "
                cp "${excludedomain_list}" "${report_dir}/domains_excluded.txt"
                while read -r excluded_domain; do
                    sed -i "s/${excluded_domain}//" "${report_dir}/domains_found.txt"
                done < "${excludedomain_list}"
                # Fixing blank lines after excluding domains
                sed -i '/^$/d' "${report_dir}/domains_found.txt"
                echo "Done!"
            fi
        else
            echo "Fail!"
            echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Make sure all necessary files exist to get all the found domains. Stopping the script."
            echo -e "Make sure all necessary files exist to get all the found domains. Stopping the script." | notify "${notify_options[@]}" -id "${notify_recon_channel}" > /dev/null 2>&1
            message "${domain}" failed
            exit 1
        fi

        echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Looking for Zone Transfer... "
        if [ -s "${tmp_dir}/zone_transfer.txt" ]; then
            cp "${tmp_dir}/zone_transfer.txt" "${report_dir}/zone_transfer.txt"
            echo "Done!"
        else
            echo "Fail!"
            echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Does not possible perfom zone transfer!"
        fi

    else
        echo "Fail!"
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Make sure the directories structure was created. Stopping the script."
        echo -e "Make sure the directories structure was created. Stopping the script." | notify "${notify_options[@]}" -id "${notify_recon_channel}" > /dev/null 2>&1
        message "${domain}" failed
        exit 1
    fi
}

organizing_subdomains(){
    subdomains_file="$1"
    if [ -s "${subdomains_file}" ]; then
        echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Getting the IPs and aliases of the domain and subdomains... "
        if [ -s "${massdns_resolvers_file}" ]; then
            "massdns" -q -r "${massdns_resolvers_file}" -t A -o S \
                -w "${tmp_dir}/resolution_massdns.tmp" "${subdomains_file}" > /dev/null 2>&1
        fi

        for d in $(cat "${subdomains_file}"); do
            dig +nocmd +nocomments +noquestion +noqr +nostats +timeout=2 -t A "${d}" >> "${tmp_dir}/resolution_dig.tmp"
        done

        for d in $(cat "${subdomains_file}"); do
            host -W 2 -t A "${d}" >> "${tmp_dir}/resolution_host.tmp"
        done
        echo "Done!"

        echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Organizing and handling domain files... "
        for file_resolution in "${tmp_dir}/resolution_massdns.tmp" "${tmp_dir}/resolution_dig.tmp" "${tmp_dir}/resolution_host.tmp"; do
            if [[ -s "${file_resolution}" ]];  then
                # Only subdomain owned by domain with IPv4
                grep -E "${IPv4_regex}$" "${file_resolution}" \
                    | awk '{ sub(/\.$/,"",$1); print $1 "\t" $NF }' \
                    | grep -F "${domain}" >> "${tmp_dir}/domains_external_ipv4.tmp"
                # Only subdomain owned by domain with IPv6
                grep -E "${IPv6_regex}$" "${file_resolution}" \
                    | awk '{ sub(/\.$/,"",$1); print $1 "\t" $NF }' \
                    | grep -F "${domain}" >> "${tmp_dir}/domains_external_ipv6.tmp"
                # Only alias
                grep -E "CNAME|is.an.alias" "${file_resolution}" \
                    | awk '{ sub(/\.$/,"",$1); print $1 "\t" $NF }' \
                    | awk -v dom="${domain}" '$1 == dom || substr($1, length($1)-length(dom)) == "." dom' \
                    | sed 's/\.$//' >> "${tmp_dir}/domains_aliases.tmp"
                # Only third party subdomain and domains
                grep -Fv "${domain}" "${file_resolution}" \
                    | awk '{print $1}' | sed 's/\.$//' \
                    | sort -u >> "${tmp_dir}/domains_thirdpart.tmp"
            fi
        done
        echo "Done!"

        # Removing private IPs
        echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Separating internal and external IPs... "
        if  [ -s "${tmp_dir}/domains_external_ipv4.tmp" ]; then
            grep -E '(^\S+\s+\b10\.\b([01]?[0-9][0-9]?|2[0-4][0-9]|25[0-5])\..*|^\S+\s+(127\..*)\b|^\S+\s+172\.1[6789]\..*|^\S+\s+172\.2[0-9]\..*|^\S+\s+172\.3[01]\..*|^\S+\s+192\.168\..*)'$ "${tmp_dir}/domains_external_ipv4.tmp" >> "${tmp_dir}/domains_internal_ipv4.tmp"
            sed -i -E '/\b10\.\b([01]?[0-9][0-9]?|2[0-4][0-9]|25[0-5])\..*$/d ; /^\S+\s+(127\..*)\b$/d; /172\.1[6789]\..*$/d ; /172\.2[0-9]\..*$/d ; /172\.3[01]\..*$/d ; /192\.168\..*$/d' "${tmp_dir}/domains_external_ipv4.tmp"
            echo "Done!"
        else
            echo "Fail!"
            echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Error organizing and handling subdomain IP files!"
            echo "Error organizing and handling subdomain IP files!" | notify "${notify_options[@]}" -id "${notify_recon_channel}" > /dev/null 2>&1
            message "${domain}" failed
            exit 1
        fi

        # Getting sudomain aliases
        echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Separating subdomain aliases... "
        if sort -u -o "${report_dir}/domains_aliases.txt" "${tmp_dir}/domains_aliases.tmp"; then
            awk '{print $1}' "${report_dir}/domains_aliases.txt" | sort -u | grep -E "${domain}$" >> "${tmp_dir}/domains_alive.tmp"
            echo "Done!"
        else
            echo "Fail!"
            echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Error organizing and handling subdomain aliases file!"
            echo "Error organizing and handling subdomain aliases file!" | notify "${notify_options[@]}" -id "${notify_recon_channel}" > /dev/null 2>&1
            message "${domain}" failed
            exit 1
        fi

        # Getting alive subdomains
        echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Separating live subdomains... "
        if [ -s "${tmp_dir}/domains_external_ipv4.tmp" ] || \
            [ -s "${tmp_dir}/domains_external_ipv6.tmp" ] || \
            [ -s "${tmp_dir}/domains_aliases.tmp" ]; then
            awk '{print $1}' "${tmp_dir}/domains_external_ipv4.tmp" \
                "${tmp_dir}/domains_external_ipv6.tmp" \
                "${tmp_dir}/domains_aliases.tmp" | sort -u >> "${tmp_dir}/domains_alive.tmp"
            echo "Done!"
        else
            echo "Fail!"
            echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Error organizing and handling subdomain alive file!"
            echo "Error organizing and handling subdomain alive file!" | notify "${notify_options[@]}" -id "${notify_recon_channel}" > /dev/null 2>&1
            message "${domain}" failed
            exit 1
        fi

        # Getting unavailable domains
        echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Separating unresponsive subdomains... "
        if [ -s "${tmp_dir}/domains_alive.tmp" ]; then
            if cp "${subdomains_file}" "${tmp_dir}/domains_without_resolution.tmp"; then
                if [ -s "${tmp_dir}/domains_without_resolution.tmp" ]; then
                    for d in $(cat "${tmp_dir}/domains_alive.tmp" | sort -u); do
                        # Escape dots so the domain is treated as a literal string,
                        # not a regex wildcard — prevents false deletions.
                        local _d_escaped="${d//./\\.}"
                        sed -i "/^${_d_escaped}$/d" "${tmp_dir}/domains_without_resolution.tmp"
                    done
                    echo "Done!"
                else
                    echo "Fail!"
                    echo "Error separating unresponsive subdomains." | notify "${notify_options[@]}" -id "${notify_recon_channel}" > /dev/null 2>&1
                    message "${domain}" failed
                    exit 1
                fi
            fi
        else
            echo "Fail!"
            echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Error organizing and handling subdomain unresponsive file!"
            echo "Error organizing and handling subdomain unresponsive file!" | notify "${notify_options[@]}" -id "${notify_recon_channel}" > /dev/null 2>&1
            message "${domain}" failed
            exit 1
        fi
 
        # Sorting out...
        echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Removing duplicate subdomains... "
        sort -u -o "${report_dir}/domains_aliases.txt" "${tmp_dir}/domains_aliases.tmp" 2> /dev/null
        sort -u -o "${report_dir}/domains_alive.txt" "${tmp_dir}/domains_alive.tmp" 2> /dev/null
        sort -u -o "${report_dir}/domains_internal_ipv4.txt" "${tmp_dir}/domains_internal_ipv4.tmp" 2> /dev/null
        sort -u -o "${report_dir}/domains_external_ipv4.txt" "${tmp_dir}/domains_external_ipv4.tmp" 2> /dev/null
        sort -u -o "${report_dir}/domains_external_ipv6.txt" "${tmp_dir}/domains_external_ipv6.tmp" 2> /dev/null
        sort -u "${tmp_dir}/domains_without_resolution.tmp" | grep -E "${domain}$" > "${report_dir}/domains_without_resolution.txt" 2> /dev/null
        sort -u -o "${report_dir}/domains_thirdpart.txt" "${tmp_dir}/domains_thirdpart.tmp" 2> /dev/null
        echo "Done!"

    else
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} The file with all domains from initial recon does not exist or is empty."
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Look all files from initial recon in ${tmp_dir} and fix the problem!"
        echo -e "The file with all domains from initial recon does not exist or is empty.\n\tLook all files from initial recon in ${tmp_dir} and fix the problem!" \
            | notify "${notify_options[@]}" -id "${notify_recon_channel}" > /dev/null 2>&1
        message "${domain}" failed
        exit 1
    fi    
}
