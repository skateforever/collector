#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * caa-enum-src                                          #
#                                                           #
#############################################################

caa-enum-src(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing CAA enum... "
    : > "${tmp_dir}/caa_enum_output.txt"
    echo -e "\ndig +short CAA \"${domain}\"" >> "${log_execution_file}"
    dig +short CAA "${domain}" 2>/dev/null | while IFS= read -r caa_record; do
        caa_tag="$(echo "${caa_record}" | awk '{print $2}')"
        caa_value="$(echo "${caa_record}" | awk '{print $3}' | tr -d '"')"
        if [[ "${caa_tag}" == "iodef" ]]; then
            # https:// URLs in iodef leak internal hostnames
            echo "${caa_value}" | grep -Eo 'https?://[^/" ]+' | sed 's|https\?://||' >> "${tmp_dir}/caa_enum_output.txt"
            # mailto: in iodef leak internal domain names
            echo "${caa_value}" | grep -Eo 'mailto:[^@]+@[^;> ]+' | sed 's/mailto:[^@]*@//' >> "${tmp_dir}/caa_enum_output.txt"
        elif [[ "${caa_tag}" == "issuewild" ]]; then
            echo -e "\nCAA issuewild detected on ${domain}: ${caa_value}" >> "${log_execution_file}"
        fi
    done
    sort -u -o "${tmp_dir}/caa_enum_output.txt" "${tmp_dir}/caa_enum_output.txt" 2>/dev/null
    echo "Done!"
}

caa-enum-src
