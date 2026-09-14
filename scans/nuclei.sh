#!/bin/bash
#############################################################
# Web application vulnerability scan with nuclei            #
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * nuclei_scan                                           #
#                                                           #
#############################################################

nuclei_scan(){
    local target="$1"
    local urls_file="$2"
    local url
    local url
    echo -en "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing nuclei scan... "
    if [ "$#" != 2 ] || [ ! -s "${urls_file}" ]; then
        echo "Fail!"
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Please, especify just 1 file to get URL from."
        echo -e "Please, especify just 1 file to get URL from." | notify "${notify_options[@]}" -id "${notify_recon_channel}" > /dev/null 2>&1
        message "${target}" failed
        exit 1
    else
        if [ -s "${urls_file}" ]; then
            if [ -d "${report_dir}" ] && [ -d "${nuclei_dir}" ]; then
                nuclei -no-color -silent -update > /dev/null 2>&1
                nuclei -no-color -silent -update-templates > /dev/null 2>&1
                local -a nucleinpids=()
                while IFS= read -r url; do
                    unset user_agent
                    user_agent="$(get_user_agent)"
                    if [ -n "${use_proxy}" ] && [ "${use_proxy}" == "yes" ]; then
                        echo "echo ${url} | nuclei ${nuclei_options[*]} -H \"User-Agent: ${user_agent}\" -proxy \"http://${proxy_ip}\"" >> "${log_execution_file}"
                        echo "${url}" | nuclei "${nuclei_options[@]}" -H "User-Agent: ${user_agent}" -proxy "http://${proxy_ip}" >> "${nuclei_scan_file}" 2>> "${log_execution_file}" &
                    else
                        echo "echo ${url} | nuclei ${nuclei_options[*]} -H \"User-Agent: ${user_agent}\"" >> "${log_execution_file}"
                        echo "${url}" | nuclei "${nuclei_options[@]}" -H "User-Agent: ${user_agent}" >> "${nuclei_scan_file}" 2>> "${log_execution_file}" &
                    fi
                    nucleinpids+=($!)
                    # Reap finished PIDs and throttle
                    local alive_count=0 newnpids=()
                    for npid in "${nucleinpids[@]}"; do
                        if kill -0 "${npid}" 2>/dev/null; then
                            ((alive_count += 1))
                            newnpids+=("${npid}")
                        fi
                    done
                    nucleinpids=("${newnpids[@]}")
                    while [[ "${alive_count}" -ge "${webapp_enum_total_processes}" ]]; do
                        sleep 1
                        alive_count=0; newnpids=()
                        for npid in "${nucleinpids[@]}"; do
                            if kill -0 "${npid}" 2>/dev/null; then
                                ((alive_count += 1))
                                newnpids+=("${npid}")
                            fi
                        done
                        nucleinpids=("${newnpids[@]}")
                    done
                done < "${urls_file}"
                # Drain all remaining nuclei jobs
                for npid in "${nucleinpids[@]}"; do
                    wait "${npid}" 2>/dev/null
                done
                echo "Done!"
                # Notifying the finds
                echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Sending nuclei scan notification... "
                grep -Ehr "\[critical\]" "${nuclei_scan_file}" | notify "${notify_options[@]}" -id "${notify_critical_channel}" > /dev/null 2>&1
                grep -Ehr "\[high\]" "${nuclei_scan_file}" | notify "${notify_options[@]}" -id "${notify_high_channel}" > /dev/null 2>&1
                echo "Done!"
            else
		echo "Fail!"
                echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Make sure the directories structure was created. Stopping the script!"
                echo -e "Make sure the directories structure was created. Stopping the script!" | notify "${notify_options[@]}" -id "${notify_recon_channel}" > /dev/null 2>&1
                message "${target}" failed
                exit 1
            fi
        else
	    echo "Fail!"
            echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Make sure the ${urls_file} exist and isn't empty."
            echo -e "Make sure the ${urls_file} exist and isn't empty." | notify "${notify_options[@]}" -id "${notify_recon_channel}" > /dev/null 2>&1
            message "${target}" failed
            exit 1
        fi
    fi
    echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Web application vunerability scan is done!"
}
