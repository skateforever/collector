#!/bin/bash
###########################################################################
# Those functions try to get all data as possible from a web application  #
#                                                                         #
# This file is an essential part of collector's execution!                #
# And is responsible to get the functions:                                #
#                                                                         #
#   * crawler_js                                                          #
#   * crawler_params                                                      #
#                                                                         #
########################################################################### 

crawler_js(){
    target="$1"
    urls_file="$2"
    echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Initializing the web application js crawler and this might take a certain time!"
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing js crawler... "
    if [ "$#" != 2 ] || [[ ! -s "${urls_file}" ]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Please, especify just 1 file to get URL from."
        echo -e "Please, especify just 1 file to get URL from." | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
        message "${target}" failed
        exit 1
    else
        if [ -d "${report_dir}" ] && [ -d "${webapp_js_dir}" ] ; then
            while IFS= read -r subdomain; do
        fi
    fi
    echo "Done!"
}

crawler_params() {
    # TODO: Put gospider to get more params
    echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Initializing the web application params crawler and this might take a certain time!"
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing params crawler... "
    while IFS= read -r url; do
        name=$(echo "${url}" | sed -e "s/http:\/\//http_/" -e "s/https:\/\//https_/" -e "s/:/_/" -e "s/\/$//" -e "s/\//_/g")
        file="${name}.params"
        echo "echo ${url} | waybackurls >> ${web_params_dir}/${file}" >> "${log_execution_file}"
        echo "${url}" | waybackurls >> "${web_params_dir}/${file}" 2>> "${log_execution_file}"
        echo "echo ${url} | katana -silent -nc -timeout ${katana_timeout} -c ${katana_threads} -p ${katana_threads} -f qurl -d 10 | grep -E \"^http\" | sort -u >> ${web_params_dir}/${file}" >> "${log_execution_file}"
        echo "${url}" | katana -silent -nc -timeout "${katana_timeout}" -c ${katana_threads} -p ${katana_threads} -f qurl -d 10 | grep -E "^http" | sort -u >> "${web_params_dir}/${file}" 2>> "${log_execution_file}"
        #katana -silent -nc -timeout "${katana_timeout}" -c ${katana_threads} -p ${katana_threads} -jc
        #katana -silent -nc -timeout "${katana_timeout}" -c ${katana_threads} -p ${katana_threads} -f qpath -d 10
        #www.example.com/path/arquivo.js
        #www.example.com/path/
        #www.example.com/path/1/
        #www.example.com/path/2/
        #www.example.com/path/3/
        unset file
    done < "${urls_file}"
    unset url
    echo "Done!"
}

