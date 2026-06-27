#!/bin/bash
#############################################################
# Create the structure                                      #
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * check_is_known_target                                 #
#   * check_directory_permission                            #
#   * create_directory_structure                            #
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

check_directory_permission(){
    [ ! -d "${output_dir}" ] && mkdir -p "${output_dir}" 2> /dev/null
    if [[ $(cd "${output_dir}" > /dev/null 2>&1 ; echo "$?") -eq 0 ]] && \
        [[ $(touch "${output_dir}/permission_to_write.txt" > /dev/null 2>&1; echo "$?") -eq 0 ]]; then
        rm -rf "${output_dir}/permission_to_write.txt"
    else
        echo -e "Please, you need to specify a ${yellow}valid directory you own or have access permission${reset}!\n"
        usage
    fi
}

create_directory_structure(){
    # Reuse-mode detector: the user is asking to re-run a webapp_* phase
    # against an existing recon_dir without -r. The previous code checked
    # ${webapp_discovery} and ${only_webapp_enum}, neither of which is ever
    # set anywhere in the project — so this branch was dead code and
    # collector always created a fresh recon_${date_recon} even when reuse
    # was intended (report C-03). Match the actual menu flags instead.
    local only_webapp_enum="no"
    if [[ "${webapp_enum_check}" == "yes" && "${recon_check}" != "yes" && "${webapp_discovery_check}" != "yes" ]]; then
        only_webapp_enum="yes"
    fi

    if [ "${directory_structure}" == "domain" ]; then
        # Create all main dirs necessaries to report and recon for domain
        if [[ "${webapp_discovery_check}" == "yes" && "${recon_check}" != "yes" ]] || [[ "${only_webapp_enum}" == "yes" ]]; then
            # Resume: pick the MOST RECENT recon_* dir that has a
            # domains_alive.txt. find's traversal order is unspecified, so
            # add `sort | tail -n1` — otherwise reuse could grab an old run.
            recon_dir="$(find "${output_dir}/${domain}" -type f -path "*/domains_alive.txt" -printf "%h\n" 2>/dev/null \
                          | sed 's|/report$||' | sort | tail -n1)"
        else
            recon_dir="${output_dir}/${domain}/recon_${date_recon}"
            mkdir -p "${recon_dir}"
            mkdir -p "${recon_dir}"/{log,tmp}
            mkdir -p "${recon_dir}"/report/{scan/{nmap,nuclei,shodan},webapp/{aquatone,enum,params,tech,javascript}}
        fi

        if [[ -z "${recon_dir}" ]] ; then
            echo "Unable to determine the initial reconnaissance structure, the execution was stopped."
            echo "You are trying to perform recon, but don't have a structure and are using a different parameter than -r|--recon with domain options."
            echo -e "You need to perform at least a basic run to get the subdomain discovered and continue the rest of the activities.\n"
            usage
        fi
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
        aquatone_log="${aquatone_files_dir}/aquatone.log"
        webapp_enum_dir="${webapp_dir}/enum"
        webapp_js_dir="${webapp_dir}/javascript"
        webapp_params_dir="${webapp_dir}/params"
        webapp_tech_dir="${webapp_dir}/tech"
    fi

    if [ "${directory_structure}" == "url" ]; then
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
        aquatone_log="${aquatone_files_dir}/aquatone.log"
        webapp_enum_dir="${webapp_dir}/enum"
        webapp_js_dir="${webapp_dir}/javascript"
        webapp_params_dir="${webapp_dir}/params"
        webapp_tech_dir="${webapp_dir}/tech"
    fi

    if [[ "${only_webapp_enum}" == "yes" ]]; then
        for d in $("${ls_bin_path}" -1t "${output_dir}/${domain}" | grep -Ev "log$"); do
            if [[ -s "${output_dir}/${domain}/${d}/report/webapp_consolidated.txt" ]]; then
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
        aquatone_log="${aquatone_files_dir}/aquatone.log"
        webapp_enum_dir="${webapp_dir}/enum"
        webapp_js_dir="${webapp_dir}/javascript"
        webapp_params_dir="${webapp_dir}/params"
        webapp_tech_dir="${webapp_dir}/tech"
    fi

    nuclei_scan_file="${nuclei_dir}/nuclei_scan.result"
    nuclei_web_fuzzing_file="${nuclei_dir}/nuclei_web_fuzzing.result"

    # Record the exact invocation at the top of the log so each run is
    # self-describing and reproducible from the artifact alone (the same
    # ${collector_command_line} also lands in the flock lockfile via
    # collector_acquire_lock; this just makes it visible in the run log).
    # redact_secrets() is applied defensively: today no CLI flag carries
    # a configured API key, but if a future flag does, this prevents it
    # from leaking into the log header.
    {
        echo "# ============================================================"
        echo "# Run started at $(date +'%Y-%m-%d %H:%M:%S %z')"
        echo "# Command: $(redact_secrets "${collector_command_line}")"
        echo "# Working dir: ${PWD}"
        echo "# Recon dir: ${recon_dir}"
        echo "# ============================================================"
    } >> "${log_execution_file}"

    echo "Directory structure created and ready to work." | tee -a "${log_execution_file}"
}
