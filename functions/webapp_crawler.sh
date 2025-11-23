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
    if [ "$#" != 2 ] && [ ! -s "${urls_file}" ]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Please, especify just 1 file to get URL from."
        echo -e "Please, especify just 1 file to get URL from." | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
        message "${target}" failed
        exit 1
    else
        if [ -d "${report_dir}" ] && [ -d "${webapp_js_dir}" ] ; then
            for subdomain in $(cat "${report_dir}/webapp_urls.txt"); do
                # curl
                # Extract all links to .js files from the URL
                curl "${curl_options[@]}" -L "${subdomain}" | grep -Eo 'src="[^"]*\.js"' | sed 's/src="//g' | sed 's/"$//g' | while read -r js_url; do
                    # Convert relative URL to absolute
                    if [[ "${js_url}" == //* ]]; then
                        js_url="https:${js_url}"
                    elif [[ "${js_url}" != http* ]]; then
                        js_url="${subdomain}/${js_url}"
                    fi

                    # Checks if it is a JavaScript file
                    if [[ "${js_url}" == *.js ]]; then
                        echo "${js_url}" >> "${tmp_dir}/js_files.tmp"
                    fi
                done

                # katana
                echo -e "\n katana ${katana_options[@]} -u ${subdomain} >> ${tmp_dir}/js_files.tmp" >> "${log_execution_file}"
                katana "${katana_options[@]}" -u "${subdomain}" >> "${tmp_dir}/js_files.tmp" 2>> "${log_execution_file}"

                # urlfinder
                echo -e "\n urlfinder ${urlfinder_options[@]} -d ${subdomain} >> ${tmp_dir}/js_files.tmp" >> "${log_execution_file}"
                urlfinder "${urlfinder_options[@]}" -d "${subdomain}" >> "${tmp_dir}/js_files.tmp" 2>> "${log_execution_file}"

                # waybackurls
                echo -e "\n echo \"${subdomain}\" | waybackurls >> ${tmp_dir}/js_files.tmp" >> "${log_execution_file}"
                echo "${subdomain}" | waybackurls >> "${tmp_dir}/js_files.tmp" 2>> "${log_execution_file}"

                for js_url in $(grep -E '\.js([?#].*)?$' "${tmp_dir}/js_files.tmp"); do
                    js_file_dir="$(echo "${js_url}" | awk -F'/' '{print $3}')"
                    js_file_name=$(basename "${js_url}")
                    [[ ! -d "${webapp_js_dir}/${js_file_dir}" ]] && mkdir -p "${webapp_js_dir}/${js_file_dir}"

                    # Checks if the URL returns HTTP status 200
                    js_status=$(curl "${curl_options[@]}" -L -o /dev/null -w "%{http_code}" --head "${js_url}")
                    if [[ "${js_status}" -eq 200 ]]; then
                        if [ ! -s "${webapp_js_dir}/${js_file_dir}/${js_file_name}" ]; then
                            echo "curl ${curl_options[@]} ${js_url} > ${webapp_js_dir}/${js_file_dir}/${js_file_name}" >> "${log_execution_file}"
                            curl "${curl_options[@]}" "${js_url}" > "${webapp_js_dir}/${js_file_dir}/${js_file_name}" 2>> "${log_execution_file}"
                        fi
                    fi
                done
            done
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

