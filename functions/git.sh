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
    local count=1
    local file target_dir git_target git_config_tmp dir_origem repo_file repo_file_dir
    for file in $("${ls_bin_path}" -1A "${webapp_enum_dir}"); do
        unset user_agent
        user_agent="$(get_user_agent)"
        if grep -q ".git/config" "${webapp_enum_dir}/${file}"; then
            target_dir="${report_dir}/$(grep -E "Target:|Url:" "${webapp_enum_dir}/${file}" | sed -e 's/^\[+\] //' | awk '{print $2}' | sed -e 's/\/$//' -e 's/http:\/\///' -e 's/https:\/\///')"
            git_target=$(grep -E "Target:|Url:" "${webapp_enum_dir}/${file}" | sed -e 's/^\[+\] //' | awk '{print $2}' | sed -e 's/\/$//')
            # Use a private temp file (700 perms) so a hostile local user
            # can't symlink-attack a fixed /tmp path or read the response.
            git_config_tmp=$(mktemp -t collector_git_config.XXXXXX) || continue
            if [ -n "${use_proxy}" ] && [ "${use_proxy}" == "yes" ]; then
                # Probe for .git/config: fast profile — a slow target here is
                # effectively a dead one and would stall the whole sweep.
                if [[ "200" -eq "$(curl "${curl_options_fast[@]}" -H "User-agent: ${user_agent}" --proxy "${proxy_ip}" -o "${git_config_tmp}" -w "%{http_code}\n" "${git_target}/.git/config")" ]] && \
                    [[ $(grep -Eq  "^\[core\]|^\[remote.*\]|^\[branch.*\]" "${git_config_tmp}"; echo "$?") -eq "0" ]]; then
                    rm -f "${git_config_tmp}"
                    echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Found .git on ${green}${git_target}${reset}!"
                    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Creating the .git directory structure for ${green}${git_target}${reset}... "
                    echo "Done!"
                    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Downloading the static and objects files from repository... "
                    echo "git-dumper --proxy \"http://${proxy_ip}\" ${git_target} \"${target_dir}\"" >> "${log_execution_file}"
                    git-dumper --proxy "http://${proxy_ip}" "${git_target}" "${target_dir}" >> "${log_execution_file}" 2>&1
                    echo "Done!"
                    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Downloading files from repository... "
                    dir_origem="${PWD}"
                    cd "${target_dir}" || continue
                    for repo_file in $(git ls-files); do
                        repo_file_dir=$(dirname "${repo_file}")
                        if [[ ! -d "${repo_file_dir}" ]] && [[ "${repo_file_dir}" != "." ]]; then
                            mkdir -p "${repo_file_dir}"
                        fi
                        echo "curl "${curl_options[@]}" -H "User-agent: ${user_agent}" -L --proxy \"${proxy_ip}\" -f \"${git_target}/${repo_file}\" -o ${repo_file}" >> "${log_execution_file}"
                        curl "${curl_options[@]}" -H "User-agent: ${user_agent}" -L --proxy "${proxy_ip}" -f "${git_target}/${repo_file}" -o "${repo_file}" &
                    done
                    while pgrep -f "curl.*${git_target}" > /dev/null; do
                       sleep 1
                    done
                    echo "Done!"
                    cd "${dir_origem}" || exit
                fi
            else
                # Probe for .git/config: fast profile (see comment above).
                if [[ "200" -eq "$(curl "${curl_options_fast[@]}" -H "User-agent: ${user_agent}" -o "${git_config_tmp}" -s -w "%{http_code}" "${git_target}/.git/config")" ]] && \
                    [[ $(grep -Eq "^\[core\]|^\[remote.*\]|^\[branch.*\]" "${git_config_tmp}"; echo "$?") -eq "0" ]]; then
                    rm -f "${git_config_tmp}"
                    echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Found .git on ${green}${git_target}${reset}!"
                    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Creating the .git directory structure for ${green}${git_target}${reset}... "
                    echo "Done!"
                    echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Downloading the static and objects files from repository... "
                    echo "git-dumper ${git_target} \"${target_dir}\"" >> "${log_execution_file}" 2>&1
                    git-dumper "${git_target}" "${target_dir}" >> "${log_execution_file}" 2>&1
                    echo "Done!"
                    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Downloading files from repository... "
                    dir_origem="${PWD}"
                    cd "${target_dir}" || continue
                    for repo_file in $(git ls-files); do
                        repo_file_dir=$(dirname "${repo_file}")
                        if [[ ! -d "${repo_file_dir}" ]] && [[ "${repo_file_dir}" != "." ]]; then
                            mkdir -p "${repo_file_dir}"
                        fi
                        echo "curl ${curl_options[@]} -H "User-agent: ${user_agent}" -L -f \"${git_target}/${repo_file}\" -o \"${repo_file}\"" >> "${log_execution_file}"
                        curl "${curl_options[@]}" -H "User-agent: ${user_agent}" -L -f "${git_target}/${repo_file}" -o "${repo_file}" &
                    done
                    while pgrep -f "curl.*${git_target}" > /dev/null; do
                        sleep 1
                    done
                    echo "Done!"
                    cd "${dir_origem}" || exit
                fi
            fi
            # Defensive cleanup if the probe didn't match and the file was
            # left behind by either branch above.
            rm -f "${git_config_tmp}"
        fi
    done
}
