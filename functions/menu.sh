#!/bin/bash
#############################################################
# Menu options file for collector script                    #
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#    * check_argument                                       #
#    * menu                                                 #
#                                                           #
#############################################################

check_argument(){
    options+=(-d --domain -dl --domain-list -ed --exclude-domains -el --exclude-domain-list -h --help -k -kill)
    options+=(-kr --kill-remove -l --limit-urls -o --output -p --proxy -r --recon -s --subdomain-brute -u --url)
    options+=(-wc --webapp-crawler -wd --webapp-discovery -we --webapp-enum -ws --webapp-scan)
    options+=(-wld --webapp-long-detection -wsd --webapp-short-detection -ww --webapp-wordlists)
    param=$1
    param_arg=$2
    for option in in "${options[@]}"; do
        if [[ "${option}" == "${param}" ]]; then
            if [[ -z "${param_arg}" ]]; then
                echo -e "The argument of ${yellow}\"$1\"${reset} it can not be ${red}\"empty\"${reset} or you forgot to inform it, please, ${yellow}specify a valid one${reset}.\n"
                usage
            else
                for option in "${options[@]}"; do
                    if [[ "${option}" == "${param_arg}" ]]; then
                        echo -e "The argument of ${yellow}\"${param}\"${reset} it can not be ${red}\"${param_arg}\"${reset}, please, ${yellow}specify a valid one${reset}.\n"
                        usage
                    fi
                done
           fi
        else
            echo -e "You're passing a parameter ${param} that doesn't exist.\n"
            usage
        fi
    done
}

menu(){
    args="$@"
    args_count="$#"
    while [ $# -ne 0 ]; do
        case $1 in
            -d|--domain)
                check_argument "$1" "$2"
                domain="$2"
                unset domain_check
                domain_check="yes"
                unset directory_structure
                directory_structure="domain"
                shift 2
                ;;
            -dl|--domain-list)
                check_argument "$1" "$2"
                if [ -s "$2" ]; then
                    domain_list=$2
                    unset domainlist_check
                    domainlist_check="yes"
                    unset directory_structure
                    directory_structure="domain"
                    shift 2
                else
                    echo -e "Please provide a valid file with domains.\n"
                    usage
                fi
                ;;
            -ed|--exclude-domains)
                check_argument "$1" "$2"
                set -f
                IFS=","
                excluded_domains+=($2)
                unset IFS
                unset excludedomain_check
                excludedomain_check="yes"
                shift 2
                ;;
            -el|--exclude-domain-list)
                check_argument "$1" "$2"
                if [ -s "$2" ]; then
                    excludedomain_list="$2"
                    unset excludedomainlist_check
                    excludedomainlist_check="yes"
                else
                    echo -e "Please provide a valid file with domains to exclude them.\n"
                    usage
                fi
                shift 2
                ;;
            -h|--help)
                usage
                ;;
            -k|--kill)
                check_argument "$1" "$2"
                if [ -z "$2" ]; then
                    echo "You need to specify a domain to kill the execution!"
                    exit 1
                else
                    unset kill_check
                    kill_check="yes"
                fi
                ;;
            -kr|--kill-remove)
                check_argument "$1" "$2"
                if [ -z "$2" ]; then
                    echo "You need to specify a domain to kill the execution!"
                    exit 1
                else
                    unset killremove_check
                    killremove_check="yes"
                fi
                ;;        
            -l|--limit-urls)
                check_argument "$1" "$2"
                if [[ -n "$2" && "$2" == ?(-)+([0-9]) ]]; then
                    limit_urls="$2"
                    unset limiturls_check
                    limiturls_check="yes"
                    shift 2
                else
                    echo -e "Specify the total number of URLs you want to test!\n"
                    usage
                fi
                ;;
            -o|--output)
                check_argument "$1" "$2"
                unset output_dir
                output_dir="$2"
                shift 2
                ;;
            -p|--proxy)
                check_argument "$1" "$2"
                unset use_proxy
                use_proxy="yes"
                proxy_ip="$(echo "$2" | sed -E 's/^\s*.*:\/\///g')"
                shift 2
                ;;
            -r|--recon)
                unset recon_check
                recon_check="yes"
                shift
                ;;
            -s|--subdomain-brute)
                check_argument "$1" "$2"
                unset IFS
                set -f
                IFS=","
                for dw in $2; do
                    if [[ -s "${dw}" ]]; then
                        dns_wordlists+=("$2")
                    else
                        echo -e "${dw} is not a valid file, please enter a valid one.\n"
                        usage
                    fi
                done
                unset IFS
                unset subdomainbrute_check
                subdomainbrute_check="yes"
                shift 2
                ;;
            -u|--url)
                check_argument "$1" "$2"
                unset url_check
                url_check="yes"
                unset directory_structure
                directory_structure="url"
                unset url_verify
                url_verify=$2
                unset url_domain
                url_domain=$(echo "${url_verify}" | sed -e 's/http.*\/\///' | awk -F'/' '{print $1}' | xargs -I {} basename {})
                shift 2
                ;;
            -wc|--webapp-crawler)
                unset webapp_crawler_check
                webapp_crawler_check="yes"
                shift
                ;;
            -wd|--webapp-discovery)
                unset webapp_discovery_check
                webapp_discovery_check="yes"
                shift
                ;;
            -we|--webapp-enum)
                unset webapp_enum_check
                webapp_enum_check=yes
                shift
                ;;
            -ws|--webapp-scan)
                unset webapp_scan_check
                webapp_scan_check="yes"
                shift
                ;;
            -wld|--webapp-long-detection)
                unset webapp_port_detect
                if [ "${#webapp_port_detect[@]}" -eq 0 ]; then
                    webapp_port_detect=("${webapp_port_long_detection[@]}")
                else
                    diff_array=$(diff <(printf "%s\n" "${webapp_port_detect[@]}") <(printf "%s\n" "${webapp_port_long_detection[@]}"))
                    if [[ ! "${#webapp_port_detect[@]}" -ne 0 ]] && [[ -n ${diff_array} ]]; then
                        echo -e "You need to specify just sort or long web port detection, not both!\n"
                        usage
                    fi
                fi
                shift
                ;;
            -wsd|--webapp-short-detection)
                unset webapp_port_detect
                if [ "${#webapp_port_detect[@]}" -eq 0 ]; then
                    webapp_port_detect=("${webapp_port_short_detection[@]}")
                else
                    diff_array=$(diff <(printf "%s\n" "${webapp_port_detect[@]}") <(printf "%s\n" "${webapp_port_short_detection[@]}"))
                    if [[ "${#webapp_port_detect[@]}" -ne 0 ]] && [[ -n ${diff_array} ]]; then
                        echo -e "You need to specify just sort or long web port detection, not both!\n"
                        usage
                    fi
                fi
                shift
                ;;
            -ww|--webapp-wordlists)
                check_argument "$1" "$2"
                set -f
                IFS=","
                for ww in $2; do
                    if [[ -s "${ww}" ]]; then
                        webapp_wordlists+=("$2")
                    else
                        echo -e "${ww} is not a valid file, please enter a valid one.\n"
                        usage
                    fi
                done
                unset IFS
                shift 2
                ;;
            -?*)
                echo -e "You are specifying the parameter ${yellow}$1${reset}, which is invalid.\n"
                usage
                ;;
            *)
                break
        esac
    done
}
