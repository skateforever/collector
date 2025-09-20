#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * dnsdumpster-src                                       #
#                                                           #
#############################################################            

dnsdumpster-src(){
            echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing dns dumpster... "
            echo "curl ${curl_options[@]} -L ${dnsdumpster_url} | grep -i -P  \"csrfmiddlewaretoken\" | grep -Po \'(?<=value=\")[^\"]*(?=\")\'" >> "${log_execution_file}"
            dnsdumpster_csrf_token=$(curl "${curl_options[@]}" -L "${dnsdumpster_url}" | grep -i -P  "csrfmiddlewaretoken" | grep -Po '(?<=value=")[^"]*(?=")')
            echo "${dnsdumpster_csrf_token}" >> "${log_execution_file}"
            echo "curl ${curl_options[@]} -X POST -b \"csrftoken=${dnsdumpster_csrf_token}\" -H 'Accept: */*' -H 'Content-Type: application/x-www-form-urlencoded' \
                -H \"Origin: ${dnsdumpster_url}\" -H \"Referer: ${dnsdumpster_url}\" \
                --data-binary \"csrfmiddlewaretoken=${dnsdumpster_csrf_token}&targetip=${domain}&user=free\" ${dnsdumpster_url}" >> "${log_execution_file}"
            curl "${curl_options[@]}" -X POST -b "csrftoken=${dnsdumpster_csrf_token}" -H 'Accept: */*' -H 'Content-Type: application/x-www-form-urlencoded' \
                -H "Origin: ${dnsdumpster_url}" -H "Referer: ${dnsdumpster_url}" \
                --data-binary "csrfmiddlewaretoken=${dnsdumpster_csrf_token}&targetip=${domain}&user=free" "${dnsdumpster_url}" \
                | grep -Po '<td class="col-md-4">\K[^<]*' | sort -u \
                | grep "${domain}" >> "${tmp_dir}/dnsdumpster_output.txt"
            echo "Done!"
            sleep 1
}

dnsdumpster-src
