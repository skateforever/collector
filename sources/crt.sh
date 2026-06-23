#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * crt-src                                               #
#                                                           #
#############################################################            

crt-src(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing crt.sh... "
    unset user_agent
    user_agent="$(get_user_agent)"
    # crt.sh queries the public CT log Postgres and can legitimately take
    # several minutes for popular domains. Use the slow profile so a short
    # connect timeout still protects against outages, but the body has time
    # to land.
    #
    # Use q=%25.<domain> (wildcard) instead of CN=<domain> so that both the
    # CN and SAN fields are searched, returning all subdomains.  Retry up to
    # 3 times on transient DB errors (crt.sh returns an HTML page instead of
    # JSON when its Postgres replica is overloaded).
    local max_retries=3
    local attempt=0
    local success=false
    local tmp_out="${tmp_dir}/crtsh_output.json"

    while [[ ${attempt} -lt ${max_retries} ]]; do
        attempt=$(( attempt + 1 ))
        echo -e "\ncurl ${curl_options_slow[@]} -H \"User-agent: ${user_agent}\" \"https://crt.sh/?q=%25.${domain}&output=json\" (attempt ${attempt})" \
            >> "${log_execution_file}"
        curl "${curl_options_slow[@]}" -H "User-agent: ${user_agent}" \
            "https://crt.sh/?q=%25.${domain}&output=json" \
            > "${tmp_out}" \
            2>> "${log_execution_file}"

        # Validate: crt.sh returns an HTML error page on DB failures.
        # Accept the result only when it is a non-empty JSON array/object.
        if [[ -s "${tmp_out}" ]] && head -c 1 "${tmp_out}" | grep -qE '^\[|\{'; then
            success=true
            break
        fi

        echo -e "\n${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} crt.sh attempt ${attempt} failed (non-JSON response). Retrying..." \
            >> "${log_execution_file}"
        sleep $(( attempt * 10 ))
    done

    if [[ "${success}" == false ]]; then
        echo -e "\n${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} crt.sh failed after ${max_retries} attempts." \
            >> "${log_execution_file}"
        # Leave an empty array so downstream parsers don't break.
        echo "[]" > "${tmp_out}"
    fi

    echo "Done!"
    sleep 1
}

crt-src
