#!/bin/bash
###########################################################################
# Those functions try to get all data as possible from a web application  #
#                                                                         #
# This file is an essential part of collector's execution!                #
# And is responsible to get the functions:                                #
#                                                                         #
#   * nuclei_scan                                                         #
#   * acunetix_scan                                                       #
#                                                                         #
########################################################################### 

nuclei_scan(){
    target="$1"
    urls_file="$2"
    echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Initializing the web application scan with nuclei and this might take a certain time!"
    echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing nuclei web application vulnerability scan..."
    if [ "$#" != 2 ] || [ ! -s "${urls_file}" ]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Please, especify just 1 file to get URL from."
        echo -e "Please, especify just 1 file to get URL from." | notify -nc -silent -id "${notify_recon_channel}" > /dev/null 2>&1
        message "${target}" failed
        exit 1
    else
        if [ -s "${urls_file}" ]; then
            if [ -d "${report_dir}" ] && [ -d "${nuclei_dir}" ]; then
                echo -e "${red}Warning:${reset} It can take a long time to execute the this scan function!"
                echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing nuclei scan... "
                nuclei -no-color -silent -update > /dev/null 2>&1
                nuclei -no-color -silent -update-templates > /dev/null 2>&1
                while IFS= read -r url; do
                    # Rotate User-Agent per URL — matches the get_user_agent
                    # pattern used by every other tool in collector. The
                    # previous approach of baking ${agent} into nuclei_options
                    # at source time was broken: ${agent} is never defined,
                    # and the \"...\" escapes split the header across argv
                    # slots (see report B-01).
                    unset user_agent
                    user_agent="$(get_user_agent)"
                    if [ -n "${use_proxy}" ] && [ "${use_proxy}" == "yes" ]; then
                        echo "echo ${url} | nuclei ${nuclei_options[@]} -H \"User-Agent: ${user_agent}\" -proxy-url \"http://${proxy_ip}\"" >> "${log_execution_file}"
                        echo "${url}" | nuclei "${nuclei_options[@]}" -H "User-Agent: ${user_agent}" -proxy-url "http://${proxy_ip}" >> "${nuclei_scan_file}" 2>> "${log_execution_file}" &
                    else
                        echo "echo ${url} | nuclei ${nuclei_options[@]} -H \"User-Agent: ${user_agent}\"" >> "${log_execution_file}"
                        echo "${url}" | nuclei "${nuclei_options[@]}" -H "User-Agent: ${user_agent}" >> "${nuclei_scan_file}" 2>> "${log_execution_file}" &
                    fi
                    while [[ "$(pgrep -acf "[n]uclei")" -ge "${webapp_enum_total_processes}" ]]; do
                        sleep 1
                    done
                done < "${urls_file}"
                # Drain the last batch of background nuclei jobs before
                # reading the result file — without this `wait`, the grep
                # below can race the final findings and notify with an
                # incomplete view (report B-06).
                while pgrep -af "[n]uclei" > /dev/null; do
                    sleep 1
                done
                echo "Done!"
                # Notifying the finds
                echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Sending nuclei scan notification... "
                grep -Ehr "\[critical\]" "${nuclei_scan_file}" | notify -nc -silent -id "${notify_critical_channel}"
                grep -Ehr "\[high\]" "${nuclei_scan_file}" | notify -nc -silent -id "${notify_high_channel}"
                echo "Done!"
            else
                echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Make sure the directories structure was created. Stopping the script!"
                unset urls_file
                echo -e "Make sure the directories structure was created. Stopping the script!" | notify -nc -silent -id "${notify_recon_channel}" > /dev/null 2>&1
                message "${target}" failed
                exit 1
            fi
        else
            echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Make sure the ${urls_file} exist and isn't empty."
            echo -e "Make sure the ${urls_file} exist and isn't empty." | notify -nc -silent -id "${notify_recon_channel}" > /dev/null 2>&1
            message "${target}" failed
            unset urls_file
            exit 1
        fi
        unset urls_file
    fi
    echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Web application vunerability scan is done!"
}

acunetix_scan(){
    target="$1"
    urls_file="$2"
    echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Initializing the web application scan with acunetix and this might take a certain time!"
    echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing acunetix web application vulnerability scan..."
    #if [ "$#" != 2 ] && [ ! -s "${urls_file}" ]; then
    #fi
}
