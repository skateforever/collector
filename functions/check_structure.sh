#!/bin/bash
#############################################################
# Create the structure                                      #
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * create_initial_directories_structure                  #
#   * check_is_known_target                                 #
#                                                           #
#############################################################

# Checking if is a know target to get the cursor position
check_is_known_target(){
    if [[ -n "$1" ]] && [[ -d "${output_dir}/$1" ]]; then
        echo "This is a known target."
    else
        echo "New target to perform reconnaissance."
    fi
}

create_initial_directories_structure(){
    if [ "${directories_structure}" == "domain" ]; then
        # Create all main dirs necessaries to report and recon for domain
        if [[ "${webapp_discovery}" == "yes" ]] || [[ "${only_webapp_enum}" == "yes" ]]; then
            #recon_dir="$("${ls_bin_path}" -d "${output_dir}/${domain}"/recon_*/ | sort -r | head -n 1)"
            recon_dir="$(find "${output_dir}/${domain}" -type f -path "*/domains_alive.txt" -printf "%h\n" 2>/dev/null | sed 's|/report$||')"
            if [[ -z "${recon_dir}" ]] ; then
                echo -e "You are trying to perform recon, but don't have a structure and are using a different parameter than -r|--recon with domain options."
                echo -e "You need to perform at least a basic run to get the subdomain discovered and continue the rest of the activities.\n"
                usage
            fi
        else
            recon_dir="${output_dir}/${domain}/recon_${date_recon}"
            mkdir -p "${recon_dir}"
            mkdir -p "${recon_dir}"/{log,tmp}
            mkdir -p "${recon_dir}"/report/{scan/{nmap,nuclei,shodan},webapp/{aquatone,enum,params,tech,javascript}}
        fi
        [[ -z "${recon_dir}" ]] && { echo "Unable to determine the initial reconnaissance structure, the execution was stopped." ; exit 1 ; }
        # log dirs
        log_dir="${recon_dir}/log"
        log_execution_file="${log_dir}/recon_${date_recon}.log"
        tmp_dir="${recon_dir}/tmp"
        # report dirs
        report_dir="${recon_dir}/report"
        scan_dir="${report_dir}/scan"
        webapp_dir="${report_dir}/webapp"
        # scan dirs
        nmap_dir="${scan_dir}/nmap"
        nuclei_dir="${scan_dir}/nuclei"
        shodan_dir="${scan_dir}/shodan"
        # webapp dirs
        aquatone_files_dir="${webapp_dir}/aquatone"
        webapp_enum_dir="${webapp_dir}/enum"
        webapp_js_dir="${webapp_dir}/javascript"
        webapp_params_dir="${webapp_dir}/params"
        webapp_tech_dir="${webapp_dir}/tech"
    fi

    if [ "${directories_structure}" == "url" ]; then
        # Create all dirs necessaries to report and recon for url
        recon_dir="${output_dir}/${url_domain}/url_${date_recon}"
        mkdir -p "${recon_dir}"
        mkdir -p "${recon_dir}"/{log,tmp}
        mkdir -p "${recon_dir}"/report/{scan/nuclei,webapp/{aquatone,enum,params,tech,javascript}}
        # log dirs
        log_dir="${recon_dir}/log"
        log_execution_file="${log_dir}/url_${date_recon}.log"
        tmp_dir="${recon_dir}/tmp"
        # report dirs
        report_dir="${recon_dir}/${url_base}/report"
        scan_dir="${report_dir}/scan"
        webapp_dir="${report_dir}/webapp"
        # scan dirs
        nuclei_dir="${scan_dir}/nuclei"
        # webapp dirs
        aquatone_files_dir="${webapp_dir}/aquatone"
        webapp_enum_dir="${webapp_dir}/enum"
        webapp_js_dir="${webapp_dir}/javascript"
        webapp_params_dir="${webapp_dir}/params"
        webapp_tech_dir="${webapp_dir}/tech"
    fi

    if [[ "${only_webapp_enum}" == "yes" ]]; then
        for d in $("${ls_bin_path}" -1t "${output_dir}/${domain}" | grep -Ev "log$"); do
            if [[ -s "${output_dir}/${domain}/${d}/report/webapp_urls.txt" ]]; then
                recon_dir="${output_dir}/${domain}/${d}"
                break
            fi
        done
        # log dirs
        log_dir="${recon_dir}/log"
        log_execution_file="${log_dir}/recon_${date_recon}.log"
        tmp_dir="${recon_dir}/tmp"    
        # report dirs
        report_dir="${recon_dir}/report"
        scan_dir="${report_dir}/scan"
        webapp_dir="${report_dir}/webapp"
        # scan dirs
        nmap_dir="${scan_dir}/nmap"
        nuclei_dir="${scan_dir}/nuclei"
        shodan_dir="${scan_dir}/shodan"
        # webapp dirs
        aquatone_files_dir="${webapp_dir}/aquatone"
        webapp_enum_dir="${webapp_dir}/enum"
        webapp_js_dir="${webapp_dir}/javascript"
        webapp_params_dir="${webapp_dir}/params"
        webapp_tech_dir="${webapp_dir}/tech"
    fi

    nuclei_scan_file="${nuclei_dir}/nuclei_scan.result"
    nuclei_web_fuzzing_file="${nuclei_dir}/nuclei_web_fuzzing.result"

    echo "Directory structure created and ready to work." | tee -a "${log_execution_file}"
}
