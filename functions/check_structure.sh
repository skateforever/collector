#!/bin/bash
#############################################################
# Create the structure                                      #
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * create_initial_directories_structure                  #
#                                                           #
#############################################################

create_initial_directories_structure(){

    if [ "${directories_structure}" == "domain" ]; then
        # Create all dirs necessaries to report and recon for domain
        mkdir -p "${output_dir}/${domain}"/{log,"domain_${date_recon}"}
        log_dir="${output_dir}/${domain}/log"
        log_execution_file="${log_dir}/domain_${date_recon}.log"
        recon_dir="${output_dir}/${domain}/domain_${date_recon}"
        # secundaries directories
        mkdir -p "${recon_dir}"/{aquatone,nmap,nuclei,report,tmp,web-data,web-params,web-tech}
        aquatone_files_dir="${recon_dir}/aquatone"
        nmap_dir="${recon_dir}/nmap"
        nuclei_dir="${recon_dir}/nuclei"
        report_dir="${recon_dir}/report"
        shodan_dir="${recon_dir}/shodan"
        if [[ "${shodan_use}" == "yes" ]] && [[ ! -d "${shodan_dir}" ]]; then
            mkdir -p "${shodan_dir}"
        fi
        tmp_dir="${recon_dir}/tmp"
        web_data_dir="${recon_dir}/web-data"
        web_params_dir="${recon_dir}/web-params"
        web_tech_dir="${recon_dir}/web-tech"
    fi

    if [ "${directories_structure}" == "url" ]; then
        # Create all dirs necessaries to report and recon for url
        mkdir -p "${output_dir}"/"${url_domain}"/{log,"url_${date_recon}"}
        log_dir="${output_dir}/${url_domain}/log"
        log_execution_file="${log_dir}/url_${date_recon}.log"
        recon_dir="${output_dir}/${url_domain}/url_${date_recon}"
    
        # secundaries directories
        mkdir -p "${recon_dir}/${url_base}"/{report,aquatone}
        report_dir="${recon_dir}/${url_base}/report"
        aquatone_files_dir="${recon_dir}/${url_base}/aquatone"
        nuclei_dir="${report_dir}"
        shodan_dir="${report_dir}"
        tmp_dir="${report_dir}"
        web_data_dir="${report_dir}"
        web_params_dir="${report_dir}"
        web_tech_dir="${report_dir}"
    fi

    if [[ "${only_web_data}" == "yes" ]]; then
        for d in $(ls -1t "${output_dir}/${domain}" | grep -Ev "log$"); do
            if [[ -s "${output_dir}/${domain}/${d}/report/web_data_urls.txt" ]]; then
                recon_dir="${output_dir}/${domain}/${d}"
                break
            fi
        done
        aquatone_files_dir="${recon_dir}/aquatone"
        nmap_dir="${recon_dir}/nmap"
        nuclei_dir="${recon_dir}/nuclei"
        report_dir="${recon_dir}/report"
        shodan_dir="${recon_dir}/shodan"
        tmp_dir="${recon_dir}/tmp"
        web_data_dir="${recon_dir}/web-data"
        web_params_dir="${recon_dir}/web-params"
        web_tech_dir="${recon_dir}/web-tech"
    fi

    nuclei_scan_file="${nuclei_dir}/nuclei_scan.result"
    nuclei_web_fuzzing_file="${nuclei_dir}/nuclei_web_fuzzing.result"

    echo "Directory structure created and ready to work." | tee -a "${log_execution_file}"
}
