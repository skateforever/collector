#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * dns-mining-src                                        #
#                                                           #
#############################################################

dns-mining-src(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing DNS mining (SPF/DMARC/MX)... "
    : > "${tmp_dir}/dns_mining_output.txt"

    # TXT / SPF records — include: and redirect= leak internal domain names
    echo -e "\ndig +short TXT \"${domain}\"" >> "${log_execution_file}"
    dig +short TXT "${domain}" 2>/dev/null | while IFS= read -r dns_mining_txt; do
        echo "${dns_mining_txt}" | grep -Eo 'include:[^ "]+' | sed 's/include://' >> "${tmp_dir}/dns_mining_output.txt"
        echo "${dns_mining_txt}" | grep -Eo 'redirect=[^ "]+' | sed 's/redirect=//' >> "${tmp_dir}/dns_mining_output.txt"
    done

    # MX records — mail exchangers may reveal internal subdomains
    echo -e "\ndig +short MX \"${domain}\"" >> "${log_execution_file}"
    dig +short MX "${domain}" 2>/dev/null | awk '{print $2}' | sed 's/\.$//' | tr '[:upper:]' '[:lower:]' | while IFS= read -r dns_mining_mx; do
        echo "${dns_mining_mx}" | grep -Ei "(\.${domain}|^${domain})$" >> "${tmp_dir}/dns_mining_output.txt"
    done

    # DMARC — _dmarc TXT, mailto: fields leak reporting domain names
    echo -e "\ndig +short TXT \"_dmarc.${domain}\"" >> "${log_execution_file}"
    dig +short TXT "_dmarc.${domain}" 2>/dev/null | grep -Eo 'mailto:[^@]+@[^;> "]+' | sed 's/mailto:[^@]*@//' | tr '[:upper:]' '[:lower:]' | while IFS= read -r dns_mining_dmarc; do
        echo "${dns_mining_dmarc}" | grep -Ei "(\.${domain}|^${domain})$" >> "${tmp_dir}/dns_mining_output.txt"
    done

    sort -u -o "${tmp_dir}/dns_mining_output.txt" "${tmp_dir}/dns_mining_output.txt" 2>/dev/null
    echo "Done!"
}

dns-mining-src
