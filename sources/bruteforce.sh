#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * bruteforce                                            #
#                                                           #
#############################################################            

bruteforce-src(){
    if [ "${#dns_wordlists[@]}" -gt 0 ]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} We will execute brute force dns with amass, gobuster and dnssearch ${#dns_wordlists[@]} time(s)."
        echo -e "\t Take a break as this step takes a while."
        echo "We will execute brute force dns with amass, gobuster and dnssearch ${#dns_wordlists[@]} time(s)."
        for list in "${dns_wordlists[@]}"; do
            index=$(printf "%s\n" "${dns_wordlists[@]}" | grep -En "^${list}$" | awk -F":" '{print $1}')
            if [ -s "${list}" ]; then
                echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Execution number ${index}... "
                echo -e "\namass enum -src -w ${list} -d ${domain}" >> "${log_execution_file}" 
                amass enum -active -src -ip -brute -d "${domain}" -w "${list}" >> "${tmp_dir}/amass_brute_output_${index}.txt" 2>> "${log_execution_file}"

                echo "dnssearch -consumers 600 -domain ${domain} -wordlist ${list}" >> "${log_execution_file}"
                dnssearch -consumers 600 -domain "${domain}" -wordlist "${list}" | \
                    grep "${domain}" >> "${tmp_dir}/dnssearch_output_${index}.txt" 2>> "${log_execution_file}"

                echo "Done!"

                #ffuf -c -u https://FUZZ."${domain}" -w "${list}" -mc 200 -rate 100 -v results.txt

                echo "gobuster dns -q -t ${gobuster_threads} --domain ${domain} --wordlist ${list}" >> "${log_execution_file}"
                gobuster dns -q -t "${gobuster_threads}" --domain "${domain}" --wordlist "${list}" >> "${tmp_dir}/gobuster_dns_output_${index}.txt" 2>> "${log_execution_file}"

                sleep 1
            else
                echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Execution number ${index}, error: ${list} does not exist or is empty!"
                continue
            fi
            unset index
        done
        unset list
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Brute force execution of amass, gobuster and dnssearch is done."
    fi
}

bruteforce-src
