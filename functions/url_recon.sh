#!/bin/bash
##############################################################
# This function will execute url recon                       #
#                                                            #
# This file is an essential part of collector's execution!   #
# And is responsible to get the functions:                   #
#                                                            #
#   * message                                                #
#                                                            #
##############################################################

url_recon(){
    (# Show the directory structure
    echo "The directory structure you will have to work with, is..."
    echo " "
    echo "${output_dir}/${url_domain}"
    echo -e "└── $(basename "${recon_dir}")"
    echo -e "    ├── log (${yellow}log dir for collector script execution${reset})"
    echo -e "    ├── report (${yellow}adjust function output files${reset})"
    echo -e "    │   ├── scan (${yellow}scan dir output files${reset})"
    echo -e "    │   │   └── nuclei (${yellow}nuclei execution output files${reset})"
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
    # Executing just the functions necessary to url check
    [[ -s "${recon_dir}/url_test.txt"  ]] && rm "${recon_dir}/url_test.txt"
    message "${url_domain}" start

    # Reachability check via dig (report C-09): the previous regex was broken —
    # '^^' double caret made the IPv4 branch unreachable, and the fragment
    # pattern matched incomplete addresses like '1.2.3'. Use the shared
    # IPv4_regex/IPv6_regex from collector.cfg and consider the target
    # reachable if either record resolves.
    local url_ipv4 url_ipv6 file
    url_ipv4="$(dig +short A    "${url_domain}" 2>/dev/null | grep -Eo "${IPv4_regex}" | head -1)"
    url_ipv6="$(dig +short AAAA "${url_domain}" 2>/dev/null | head -1)"
    if [[ -n "${url_ipv4}" ]] || [[ -n "${url_ipv6}" ]]; then
        echo "${url_domain}" > "${recon_dir}/url_test.txt"
    else
        message "${url_domain}" failed
        exit 1
    fi

    if [[ -s "${recon_dir}/url_test.txt" ]]; then
        webapp_enum "${url_domain}" "${recon_dir}/url_test.txt"
        robots_txt
        # sitemap_xml: use the seed url_test.txt (single host in URL mode);
        # any hints from robots.txt bodies are picked up internally.
        sitemap_xml "${recon_dir}/url_test.txt"
    fi

    # Pass both target and urls_file (report C-04): the previous call
    # was `webapp_enum "${report_dir}/robots_urls.txt"` (single arg),
    # which left urls_file empty inside webapp_enum and made the
    # [ -s "${urls_file}" ] guard fail.
    [[ -s "${report_dir}/robots_urls.txt" ]] && webapp_enum "${url_domain}" "${report_dir}/robots_urls.txt"
    [[ -s "${report_dir}/sitemap_urls.txt" ]] && webapp_enum "${url_domain}" "${report_dir}/sitemap_urls.txt"

    # Iterate over BOTH files and pass ${file}, not the hard-coded
    # url_test.txt — otherwise robots_urls.txt is never crawled/scanned.
    # Also adds ${url_domain} as the first arg to aquatone_screenshot
    # (report C-04).
    for file in "${recon_dir}/url_test.txt" "${report_dir}/robots_urls.txt" "${report_dir}/sitemap_urls.txt"; do
        if [[ -s "${file}" ]]; then
            webapp_tech         "${url_domain}" "${file}"
            crawler_js          "${url_domain}" "${file}"
            crawler_params      "${url_domain}" "${file}"
            nuclei_scan         "${url_domain}" "${file}"
            #acunetix_scan      "${url_domain}" "${file}"
            aquatone_screenshot "${url_domain}" "${file}"
            git_rebuild
        fi
    done

    build_llm_prompt
    db_usage
    start_app_report
    message "${url_verify}" finished
    rm "${recon_dir}/url_test.txt" > /dev/null 2>&1) 2>> "${log_execution_file}" | tee -a "${log_execution_file}"
}
