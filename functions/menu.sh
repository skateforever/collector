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
    options+=(-d --domain -dl --domain-list -e --exclude-domains -el --exclude-domain-list -k -kill -ka --kill-all -l --limit-urls -o --output -p --proxy -r --recon)
    options+=(-s --subdomain-brute -u --url -wd --webapp-discovery -we --webapp-enum -wld --webapp-long-detection -wsd --webapp-short-detection -ww --webapp-wordlists)
    declare -A valid_option
    for option in "${options[@]}"; do
        valid_option["${option}"]=1
    done
    if [[ ! -v "${valid_option[$1]}" ]]; then
        echo -e "You are specifying the parameter ${yellow}$1${reset}, which is invalid.\n"
        usage
    fi
    if [[ -v "${valid_option[$2]}" ]]; then
        [[ -z $2 ]] && value="empty" || value="$2"
        echo -e "The argument of ${yellow}\"$1\"${reset} it can not be ${red}\"${value}\"${reset}, please, ${yellow}specify a valid one${reset}.\n"
        usage
    fi
}

menu(){
    args="$@"
    args_count="$#"
    while [ $# -ne 0 ]; do
        case $1 in
            -d|--domain)
                check_argument "$1" "$2"
                if [[ -n "${url_2_verify}" ]]; then
                    echo -e "You can only use \"-d|--domain\" or \"-u|--url\", never both together!\n"
                    usage
                elif [[ -s "${domain_list}" ]]; then
                    echo -e "You can only use \"-d|--domain\" or \"-dl|--domain-list\", never both together!\n"
                    usage
                else
                    domain="$2"
                    unset directories_structure
                    directories_structure="domain"
                    shift 2
                fi
                ;;
            -dl|--domain-list)
                check_argument "$1" "$2"
                if [[ -n "${url_2_verify}" ]]; then
                    echo -e "You can only use \"-dl|--domain-list\" or \"-u|--url\", never both together!\n"
                    usage
                elif [[ -s "${domain_list}" ]]; then
                    echo -e "You can only use \"-dl|--domain-list\" or \"-d|--domain\", never both together!\n"
                    usage
                else
                    if [ -s "$2" ]; then
                        domain_list=$2
                        unset directories_structure
                        directories_structure="domain"
                        shift 2
                    else
                        echo -e "Please provide a valid file with domains.\n"
                        usage
                    fi
                fi
                ;;
            -e|--exclude-domains)
                check_argument "$1" "$2"
                if [[ -n "${url_2_verify}" ]]; then
                    echo -e "You can only use this (-e|--exlude-domains) option with \"-d|--domain\"!\n"
                    usage
                fi
                set -f
                IFS=","
                excluded+=("$2")
                unset IFS
                shift 2
                ;;
            -el|--exclude-domain-list)
                if [ -s "$2" ]; then
                    exclude_domains_list="$2"
                    shift 2
                fi
                ;;
            -k|--kill)
                check_argument "$1" "$2"
                if [ -z "$2" ]; then
                    echo "You need to specify a domain to kill the execution!"
                    exit 1
                else
                    kill_collector "$2"
                fi
                ;;
            -kr|--kill-remove)
                check_argument "$1" "$2"
                if [ -z "$2" ]; then
                    echo "You need to specify a domain to kill the execution!"
                    exit 1
                else
                    kill_collector "$2"
                    rm -rf "$(find / -iname "$(find / -iname "$2" -type d -exec ls -1 {} \; 2>/dev/null | grep recon_ | tail -n1)" -type d 2> /dev/null)"
                fi
                ;;        
            -l|--limit-urls)
                check_argument "$1" "$2"
                if [[ -n "${url_2_verify}" ]]; then
                    echo -e "You can only use this (-l|--limit-urls) option with \"-d|--domain\"!\n"
                    usage
                fi
                if [[ -n "$2" && "$2" == ?(-)+([0-9]) ]]; then
                    limit_urls="$2"
                    shift 2
                else
                    echo -e "Specify the total number of URLs you want to test!\n"
                    usage
                fi
                ;;
            -o|--output)
                check_argument "$1" "$2"
                [ ! -d "$2" ] && mkdir -p "$2" 2> /dev/null
                if [[ $(cd "$2" > /dev/null 2>&1 ; echo "$?") -eq 0 ]] && [[ $(touch "$2/permission_to_write.txt" > /dev/null 2>&1; echo "$?") -eq 0 ]]; then
                    unset output_dir
                    output_dir="$(echo "$2" | sed -e 's/\/$//')"
                    shift 2
                    rm -rf "${output_dir}/permission_to_write.txt"
                else
                    echo -e "Please, you need to specify a ${yellow}valid directory you own or have access permission${reset}!\n"
                    usage
                fi
                ;;
            -p|--proxy)
                check_argument "$1" "$2"
                use_proxy="yes"
                proxy_ip="$(echo "$2" | sed -E 's/^\s*.*:\/\///g')"
                shift 2
                ;;
            -r|--recon)
                if [[ -n "${url_2_verify}" ]]; then
                    echo -e "With this option (-re|--recon) You can only use \"-d|--domain\"!\n"
                    usage
                fi
                unset recon_check
                recon_check="yes"
                shift
                ;;
            -s|--subdomain-brute)
                check_argument "$1" "$2"
                if [[ -n "${url_2_verify}" ]]; then
                    echo -e "You can only use this (-s|--subdomain-brute) option with \"-d|--domain\"!\n"
                    usage
                fi
                set -f
                IFS=","
                dns_wordlists+=("$2")
                unset IFS
                shift 2
                ;;
            -u|--url)
                check_argument "$1" "$2"
                if [[ -n "${domain}" ]]; then
                    echo -e "You can only use \"-u|--url\" or \"-d|--domain\", never both together!\n"
                    usage
                elif [[ -s "${domain_list}" ]]; then
                    echo -e "You can only use \"-u|--url\" or \"-dl|--domain-list\", never both together!\n"
                    usage
                else
                    [[ -n "$2" ]] && status_code=$(curl -o /dev/null -kLs -w "%{http_code}" "$2")
                    if [[ -z ${status_code} || "${status_code}" -eq "000" ]];then
                        echo -e "You need specify a valid URL!\n"
                        usage
                    else
                        unset url_domain
                        unset url_2_verify
                        unset directories_structure
                        url_2_verify=$2
                        url_domain=$(echo "${url_2_verify}" | sed -e 's/http.*\/\///' | awk -F'/' '{print $1}' | xargs -I {} basename {})
                        directories_structure="url"
                        shift 2
                    fi
                fi
                unset status_code
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
            -wld|--webapp-long-detection)
                if [ "${#webapp_port_detect[@]}" -eq 0 ]; then
                    webapp_port_detect=("${webapp_port_long_detection[@]}")
                else
                    diff_array=$(diff <(printf "%s\n" "${webapp_port_detect[@]}") <(printf "%s\n" "${webapp_port_long_detection[@]}"))
                    if [[ ! "${#webapp_port_detect[@]}" -ne 0 ]] && [[ -n ${diff_array} ]]; then
                        echo -e "You need to specify just sort or long web port detection, not both!\n"
                        unset web_port_detect
                        usage
                    fi
                fi
                shift
                ;;
            -wsd|--webapp-short-detection)
                if [ "${#webapp_port_detect[@]}" -eq 0 ]; then
                    webapp_port_detect=("${webapp_port_short_detection[@]}")
                else
                    diff_array=$(diff <(printf "%s\n" "${webapp_port_detect[@]}") <(printf "%s\n" "${webapp_port_short_detection[@]}"))
                    if [[ "${#webapp_port_detect[@]}" -ne 0 ]] && [[ -n ${diff_array} ]]; then
                        echo -e "You need to specify just sort or long web port detection, not both!\n"
                        unset webapp_port_detect
                        usage
                    fi
                fi
                shift
                ;;
            -ww|--webapp-wordlists)
                check_argument "$1" "$2"
                set -f
                IFS=","
                webapp_wordlists+=("$2")
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
