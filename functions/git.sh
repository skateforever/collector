#!/bin/bash
#############################################################
# Looking for git repository                                #
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * git_rebuild                                           #
#                                                           #
############################################################# 

git_rebuild(){
    echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Looking for git repository on webapp_enum directory..."
    echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} This function has no 100% guaranty to completely recover the .git repository."
    count=1
    proxy_port=8118
    for file in $(ls -1A "${webapp_enum_dir}"); do
        if grep -q ".git/config" "${webapp_enum_dir}/${file}"; then
            target_dir="${report_dir}/$(grep -E "Target:|Url:" "${webapp_enum_dir}/${file}" | sed -e 's/^\[+\] //' | awk '{print $2}' | sed -e 's/\/$//' -e 's/http:\/\///' -e 's/https:\/\///')"
            target=$(grep -E "Target:|Url:" "${webapp_enum_dir}/${file}" | sed -e 's/^\[+\] //' | awk '{print $2}' | sed -e 's/\/$//')
            if [ -n "${proxy_ip}" ] && [ "${proxy_ip}" == "yes" ]; then
                if [[ "200" -eq "$(curl "${curl_options[@]}" --proxy "${proxy_ip}" -o /tmp/git_config -w "%{http_code}\n" "${target}/.git/config")" ]] && \
                    [[ $(grep -Eq  "^\[core\]|^\[remote.*\]|^\[branch.*\]" /tmp/git_config; echo "$?") -eq "0" ]]; then
                    rm -rf /tmp/git_config
                    echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Found .git on ${green}${target}${reset}!"
                    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Creating the .git directory structure for ${green}${target}${reset}... "
                    echo "Done!"
                    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Downloading the static and objects files from repository... "
                    echo "git-dumper --proxy \"http://${proxy_ip}\" ${target} \"${target_dir}\"" >> "${log_execution_file}"
                    git-dumper --proxy "http://${proxy_ip}" "${target}" "${target_dir}" >> "${log_execution_file}" 2>&1
                    echo "Done!"
                    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Downloading files from repository... "
                    dir_origem="${PWD}"
                    cd "${target_dir}" || exit
                    for repo_file in $(git ls-files); do
                        repo_file_dir=$(dirname "${repo_file}")
                        if [[ ! -d "${repo_file_dir}" ]] && [[ "${repo_file_dir}" != "." ]]; then
                            mkdir -p "${repo_file_dir}"
                        fi
                        echo "curl "${curl_options[@]}" -L --proxy \"${proxy_ip}\" -f \"${target}/${repo_file}\" -o ${repo_file}" >> "${log_execution_file}"
                        curl "${curl_options[@]}" -L --proxy "${proxy_ip}" -f "${target}/${repo_file}" -o "${repo_file}" &
                    done
                    while pgrep -f curl > /dev/null; do
                       sleep 1
                    done
                    echo "Done!"
                    cd "${dir_origem}" || exit
                fi
            else
                if [[ "200" -eq "$(curl "${curl_options[@]}" -o /tmp/git_config -s -w "%{http_code}" "${target}/.git/config")" ]] && \
                    [[ $(grep -Eq "^\[core\]|^\[remote.*\]|^\[branch.*\]" /tmp/git_config; echo "$?") -eq "0" ]]; then
                    rm -rf /tmp/git_config
                    echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Found .git on ${green}${target}${reset}!"
                    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Creating the .git directory structure for ${green}${target}${reset}... "
                    echo "Done!"
                    echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Downloading the static and objects files from repository... "
                    echo "git-dumper ${target} \"${target_dir}\"" >> "${log_execution_file}" 2>&1
                    git-dumper "${target}" "${target_dir}" >> "${log_execution_file}" 2>&1
                    echo "Done!"
                    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Downloading files from repository... "
                    dir_origem="${PWD}"
                    cd "${target_dir}" || exit
                    for repo_file in $(git ls-files); do
                        repo_file_dir=$(dirname "${repo_file}")
                        if [[ ! -d "${repo_file_dir}" ]] && [[ "${repo_file_dir}" != "." ]]; then
                            mkdir -p "${repo_file_dir}"
                        fi
                        echo "curl ${curl_options[@]} -L -f \"${target}/${repo_file}\" -o \"${repo_file}\"" >> "${log_execution_file}"
                        curl "${curl_options[@]}" -L -f "${target}/${repo_file}" -o "${repo_file}" &
                    done
                    while pgrep -f curl > /dev/null; do
                        sleep 1
                    done
                    echo "Done!"
                    cd "${dir_origem}" || exit
                fi
            fi
        fi
    done
}
