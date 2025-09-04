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
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing params crawler with wayback and katana... "
    if [ "$#" != 2 ] && [ ! -s "${urls_file}" ]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Please, especify just 1 file to get URL from."
        echo -e "Please, especify just 1 file to get URL from." | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
        message "${target}" failed
        exit 1
    else
        if [ -d "${report_dir}" ] && [ -d "${webapp_js_dir}" ] ; then
            # Extrai todos os links para arquivos .js da URL
            curl -H "${agent}" -L -s "$url" | grep -Eo 'src="[^"]*\.js"' | sed 's/src="//g' | sed 's/"$//g' | while read -r js_url; do
                # Converte URL relativa em absoluta
                if [[ "$js_url" == //* ]]; then
                    js_url="https:$js_url"
                elif [[ "$js_url" != http* ]]; then
                    js_url="$url/$js_url"
                fi
            
                # Verifica se é um arquivo JavaScript
                if [[ "$js_url" == *.js ]]; then
                    # Verifica se a URL retorna status HTTP 200
                    http_status=$(curl -H "${agent}" -L -s -o /dev/null -w "%{http_code}" --head "$js_url")
                    if [ "$http_status" -eq 200 ]; then
                        nome_arquivo=$(basename "$js_url")
                        if [ ! -f "$dominio/js_files/$nome_arquivo" ]; then
                            echo "Baixando: $js_url (Status: $http_status)"
                            curl -s "$js_url" -o "$dominio/js_files/$nome_arquivo"
                        else
                            echo "Arquivo já existe: $js_url (Status: $http_status)"
                        fi
                    else
                        echo "URL não acessível: $js_url (Status: $http_status)"
                    fi
                fi
                echo $js_url        
                # Baixa o arquivo se for .js e não existir localmente
                if [[ "$js_url" == *.js ]]; then
                    nome_arquivo=$(basename "$js_url")
                    if [ ! -f "$dominio/js_files/$nome_arquivo" ]; then
                        echo "Baixando: $js_url"
                        curl -s "$js_url" -o "$dominio/js_files/$nome_arquivo"
                    fi
                fi
            done
        fi
    fi
}

crawler_params() {
    # TODO: Put gospider to get more params
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing params crawler with wayback and katana... "
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

