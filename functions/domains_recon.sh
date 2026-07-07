#!/bin/bash
#############################################################
# The domain recon execution file                           #
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * domains_recon                                         #
#                                                           #
############################################################# 

domains_recon(){
    (# Show the directory structure
    cleanup_on_exit(){
        rm -f "${tmp_dir}"/vhost_pair_*.tmp 2>/dev/null
        rm -f "${tmp_dir}"/vhost_probe_worker_*.txt 2>/dev/null
        rm -rf "${tmp_dir}"/resolve_* 2>/dev/null
        rm -f "${tmp_dir}"/_alive_sorted.tmp 2>/dev/null
    }
    trap cleanup_on_exit EXIT

    echo "The directory structure you will have to work with, is..."
    echo " "
    echo "${output_dir}/${domain}"
    echo -e "└── $(basename "${recon_dir}")"
    echo -e "    ├── log (${yellow}log dir for collector script execution${reset})"
    echo -e "    ├── report (${yellow}adjust function output files${reset})"
    echo -e "    │   ├── scan (${yellow}scan dir output files${reset})"
    echo -e "    │   │   ├── nmap (${yellow}nmap executionr output files${reset})"
    echo -e "    │   │   ├── nuclei (${yellow}nuclei execution output files${reset})"
    echo -e "    │   │   └── shodan (${yellow}shodan execution output files${reset})"
    echo -e "    │   └── webapp (${yellow}webapp data dir for output files${reset})"
    echo -e "    │       ├── aquatone (${yellow}aquatone output files${reset})"
    echo -e "    │       ├── enum (${yellow}gobuster and dirsearch output${reset})"
    echo -e "    │       ├── javascript (${yellow}downloaded JS files to seek params and api keys${reset})"
    echo -e "    │       ├── params (${yellow}katana and waybackurl output${reset})"
    echo -e "    │       └── tech (${yellow}response headers for detection technologie using curl or httpx output${reset})"
    echo -e "    └── tmp (${yellow}subdomains recon tmp files${reset})"
    echo " "
    echo -e "${red}Attention:${reset} The output from all tools used here will be placed in background and treated later."
    echo -e "\t   If you need look the output in execution time, you need to \"tail\" the files."
    echo " "
    # Execute all functions
    message "${domain}" start

    # Only web app discovery
    if [[ "${webapp_discovery_check}" == "yes" ]] && [[ -s "${report_dir}/domains_alive.txt" ]] && \
        [[ "${recon_check}" != "yes" ]]; then
          webapp_alive "${domain}" "${report_dir}/domains_alive.txt"
          build_consolidated_urls
          webapp_tech "${domain}" "${report_dir}/webapp_consolidated.txt"
          emails_recon
          diff_artifacts
          # build_llm_prompt MUST run before record_history: the latter
          # decides status=finished only when llm-prompt.txt exists on disk.
          build_llm_prompt
          record_history
          db_usage
          start_app_report
          run_summary "${domain}"
          message "${domain}" finished
          exit 0
    fi

    # Only web app crawler
    if [[ "${webapp_crawler_check}" == "yes" ]] && [[ -s "${report_dir}/webapp_consolidated.txt" ]] && \
        [[ "${recon_check}" == "no" || -z "${recon_check}" ]]; then
          crawler_js "${domain}" "${report_dir}/webapp_consolidated.txt"
          crawler_params "${domain}" "${report_dir}/webapp_consolidated.txt"
          source "${collector_path}/sources/spider.sh"
          spider_src "${report_dir}/webapp_consolidated.txt"
          if [[ -s "${tmp_dir}/spider_output.txt" ]]; then
              grep -Ei "(\.${domain}$|^${domain}$)" "${tmp_dir}/spider_output.txt" \
                  | sort -u >> "${report_dir}/domains_found.txt"
              sort -u -o "${report_dir}/domains_found.txt" "${report_dir}/domains_found.txt"
          fi
          diff_artifacts
          build_llm_prompt
          record_history
          db_usage
          start_app_report
          run_summary "${domain}"
          message "${domain}" finished
          exit 0
    fi

    # Only web app scan
    if [[ "${webapp_scan_check}" == "yes" ]] && [[ -s "${report_dir}/webapp_consolidated.txt" ]] && \
        [[ "${recon_check}" == "no" || -z "${recon_check}" ]]; then
          nuclei_scan "${domain}" "${report_dir}/webapp_consolidated.txt"
          acunetix_scan "${domain}" "${report_dir}/webapp_consolidated.txt"
          diff_artifacts
          build_llm_prompt
          record_history
          db_usage
          start_app_report
          run_summary "${domain}"
          message "${domain}" finished
          exit 0
    fi

    # Only recon discovery (domain and subdomains)
    if [[ "${recon_check}" == "yes" ]]; then
        subdomains_recon
        joining_subdomains
        diff_domains
        if [[ -s "${report_dir}/domains_diff.txt" ]]; then
            organizing_subdomains "${report_dir}/domains_diff.txt"
        else
            organizing_subdomains "${report_dir}/domains_found.txt"
        fi
        infra_data
        nmap_scan
        shodan_scan
        if [[ "${webapp_discovery_check}" == "yes" ]]; then
            webapp_alive "${domain}" "${report_dir}/domains_alive.txt"
            if [[ "${vhost_validation_check}" == "yes" ]]; then
            source "${collector_path}/sources/vhost-check.sh"
            [[ -s "${report_dir}/domains_without_resolution.txt" ]] && [[ -s "${report_dir}/infra_ipv4.txt" ]] && \
                vhost_check "${report_dir}/domains_without_resolution.txt" "${report_dir}/infra_ipv4.txt"
            # Merge vhost_check STRONG findings into domains_found.txt / domains_alive.txt.
            # The IP is already known (from infra_ipv4.txt), so pull it from etc_hosts_file.txt
            # (format: "ip\tvhost") rather than doing a fresh DNS lookup.
            if [[ -s "${tmp_dir}/vhost_subdomains_strong.tmp" ]]; then
                awk '{print $1}' "${tmp_dir}/vhost_subdomains_strong.tmp" \
                    | grep -Ei "(\.${domain}$|^${domain}$)" | sort -u >> "${report_dir}/domains_found.txt"
                sort -u -o "${report_dir}/domains_found.txt" "${report_dir}/domains_found.txt"
                while IFS=$'\t' read -r vc_ip vc_host; do
                    echo "${vc_host}"$'\t'"${vc_ip}" >> "${report_dir}/domains_external_ipv4.txt"
                    echo "${vc_host}" >> "${report_dir}/domains_alive.txt"
                done < "${report_dir}/etc_hosts_file.txt"
                sort -u -o "${report_dir}/domains_external_ipv4.txt" "${report_dir}/domains_external_ipv4.txt"
                sort -u -o "${report_dir}/domains_alive.txt" "${report_dir}/domains_alive.txt"
            fi
            source "${collector_path}/sources/vhost-probe.sh"
            [[ -s "${report_dir}/infra_ipv4.txt" ]] && \
                vhost_probe "${report_dir}/infra_ipv4.txt"
            # Merge vhost_probe findings into domains_found.txt and resolve new entries
            if [[ -s "${tmp_dir}/vhost_probe_output.txt" ]]; then
                grep -Ei "(\.${domain}$|^${domain}$)" "${tmp_dir}/vhost_probe_output.txt" \
                    | sort -u >> "${report_dir}/domains_found.txt"
                sort -u -o "${report_dir}/domains_found.txt" "${report_dir}/domains_found.txt"
                # Resolve new vhost_probe entries so they populate domains_alive.txt
                # and domains_external_ipv4.txt for downstream nmap/shodan cycles.
                grep -Ei "(\.${domain}$|^${domain}$)" "${tmp_dir}/vhost_probe_output.txt" \
                    | sort -u > "${tmp_dir}/vhost_probe_new.tmp"
                if [[ -s "${tmp_dir}/vhost_probe_new.tmp" ]]; then
                    local vp_tls_pat vp_new_host vp_new_ip
                    vp_tls_pat="$(echo "${webapp_tls_ports[@]}" | tr ' ' '|')"
                    while IFS= read -r vp_new_host; do
                        vp_new_ip="$(dig +short A "${vp_new_host}" 2>/dev/null | grep -Eo "${IPv4_regex}" | head -1)"
                        if [[ -n "${vp_new_ip}" ]]; then
                            echo "${vp_new_host}"$'\t'"${vp_new_ip}" >> "${report_dir}/domains_external_ipv4.txt"
                            echo "${vp_new_host}" >> "${report_dir}/domains_alive.txt"
                            echo "${vp_new_ip}" >> "${report_dir}/infra_ipv4.txt"
                            # Build vhost URLs so build_consolidated_urls picks them up.
                            # vhost_probe probes HTTP only (F-06 aside), so generate
                            # both http and https variants for all configured ports.
                            for vp_port in "${webapp_port_detect[@]}"; do
                                local vp_proto="http"
                                [[ "${vp_port}" =~ ^(${vp_tls_pat})$ ]] && vp_proto="https"
                                if [[ "${vp_proto}" == "http" && "${vp_port}" == "80" ]] || \
                                   [[ "${vp_proto}" == "https" && "${vp_port}" == "443" ]]; then
                                    echo "${vp_proto}://${vp_new_host}"
                                else
                                    echo "${vp_proto}://${vp_new_host}:${vp_port}"
                                fi
                            done >> "${report_dir}/vhost_urls.txt"
                        fi
                    done < "${tmp_dir}/vhost_probe_new.tmp"
                    sort -u -o "${report_dir}/domains_external_ipv4.txt" "${report_dir}/domains_external_ipv4.txt"
                    sort -u -o "${report_dir}/domains_alive.txt" "${report_dir}/domains_alive.txt"
                    sort -u -o "${report_dir}/infra_ipv4.txt" "${report_dir}/infra_ipv4.txt"
                    sort -u -o "${report_dir}/vhost_urls.txt" "${report_dir}/vhost_urls.txt"
                fi
            fi
            fi  # end vhost_validation_check
            # Build the consolidated URL list once — after both vhost_check and
            # vhost_probe have finished writing to vhost_urls.txt. The call that
            # was previously inside vhost_check() was removed so that probe hits
            # are included here in a single pass (F-05 fix).
            build_consolidated_urls
            webapp_tech "${domain}" "${report_dir}/webapp_consolidated.txt"
        fi
        emails_recon
        if [[ "${webapp_crawler_check}" == "yes" && "${webapp_enum_check}" != "yes" ]]; then
            if [[ "${webapp_discovery_check}" != "yes" ]]; then
                echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Warning: webapp_crawler_check requires webapp_discovery_check to build the URL list. Skipping crawler."
            else
                crawler_js "${domain}" "${report_dir}/webapp_consolidated.txt"
                crawler_params "${domain}" "${report_dir}/webapp_consolidated.txt"
                source "${collector_path}/sources/spider.sh"
                spider_src "${report_dir}/webapp_consolidated.txt"
                # Merge spider findings into domains_found.txt and resolve new entries
                if [[ -s "${tmp_dir}/spider_output.txt" ]]; then
                    grep -Ei "(\.${domain}$|^${domain}$)" "${tmp_dir}/spider_output.txt" \
                        | sort -u >> "${report_dir}/domains_found.txt"
                    sort -u -o "${report_dir}/domains_found.txt" "${report_dir}/domains_found.txt"
                    grep -Ei "(\.${domain}$|^${domain}$)" "${tmp_dir}/spider_output.txt" \
                        | sort -u > "${tmp_dir}/spider_new.tmp"
                    if [[ -s "${tmp_dir}/spider_new.tmp" ]]; then
                        local sp_new_host sp_new_ip
                        while IFS= read -r sp_new_host; do
                            sp_new_ip="$(dig +short A "${sp_new_host}" 2>/dev/null | grep -Eo "${IPv4_regex}" | head -1)"
                            if [[ -n "${sp_new_ip}" ]]; then
                                echo "${sp_new_host}"$'\t'"${sp_new_ip}" >> "${report_dir}/domains_external_ipv4.txt"
                                echo "${sp_new_host}" >> "${report_dir}/domains_alive.txt"
                                echo "${sp_new_ip}" >> "${report_dir}/infra_ipv4.txt"
                            fi
                        done < "${tmp_dir}/spider_new.tmp"
                        sort -u -o "${report_dir}/domains_external_ipv4.txt" "${report_dir}/domains_external_ipv4.txt"
                        sort -u -o "${report_dir}/domains_alive.txt" "${report_dir}/domains_alive.txt"
                        sort -u -o "${report_dir}/infra_ipv4.txt" "${report_dir}/infra_ipv4.txt"
                    fi
                fi
            fi
        fi
        if [[ "${webapp_scan_check}" == "yes" && "${webapp_enum_check}" != "yes" ]]; then
            nuclei_scan "${domain}" "${report_dir}/webapp_consolidated.txt"
            #acunetix_scan "${domain}" "${report_dir}/webapp_consolidated.txt"
        fi
        [[ "${recon_check}" == "yes" && "${webapp_enum_check}" != "yes" ]] && \
            { diff_artifacts; build_llm_prompt; record_history; db_usage; start_app_report; run_summary "${domain}"; message "${domain}" finished; exit 0; }
    fi

    if [[ "${webapp_enum_check}" == "yes" ]]; then
        webapp_enum "${domain}" "${report_dir}/webapp_consolidated.txt"
        robots_txt
        [[ -s "${report_dir}/robots_urls.txt" ]] && webapp_enum "${domain}" "${report_dir}/robots_urls.txt"
        # sitemap_xml runs AFTER robots_txt so it can pick up any
        # "Sitemap: <url>" hints captured in the robots bodies. The output
        # file ${report_dir}/sitemap_urls.txt is then treated exactly like
        # robots_urls.txt by the downstream loop.
        sitemap_xml "${report_dir}/webapp_consolidated.txt"
        [[ -s "${report_dir}/sitemap_urls.txt" ]] && webapp_enum "${domain}" "${report_dir}/sitemap_urls.txt"

        # Use a loop variable name that doesn't collide with the global
        # `urls_file` used (and unset) inside aquatone_screenshot /
        # nuclei_scan / webapp_tech / webapp_enum. Otherwise, after the
        # first callee runs, `${urls_file}` is empty for the remaining
        # callees in the same iteration (report B-05).
        local current_urls_file
        for current_urls_file in "${report_dir}/webapp_consolidated.txt" "${report_dir}/robots_urls.txt" "${report_dir}/sitemap_urls.txt"; do
            if [[ -s "${current_urls_file}" ]]; then
                aquatone_screenshot "${domain}" "${current_urls_file}"
                if [[ "${webapp_crawler_check}" == "yes" ]]; then
                    crawler_js "${domain}" "${current_urls_file}"
                    crawler_params "${domain}" "${current_urls_file}"
                fi
                if [[ "${webapp_scan_check}" == "yes" ]]; then
                    nuclei_scan "${domain}" "${current_urls_file}"
                    #acunetix_scan "${domain}" "${current_urls_file}"
                fi
            fi
        done
        git_rebuild
    fi
    diff_artifacts
    build_llm_prompt
    record_history
    db_usage
    start_app_report
    run_summary "${domain}"
    message "${domain}" finished) 2>> "${log_execution_file}" | tee -a "${log_execution_file}"
}
