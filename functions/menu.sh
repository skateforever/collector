check_argument(){
    options+=(-d --domain -dl --domain-list -e --exclude-domains -el --exclude-domains-list -k -kill -ka --kill-all -l --limit-urls -o --output -p --proxy -r --recon)
    options+=(-s --subdomain-brute -u --url -we --webapp-enum -wld --webapp-long-detection -wsd --webapp-short-detection -wtd --webapp-tool-detection -ww --webapp-wordlists)
    if [[ "${options[*]}" =~ $2 ]]; then
        echo -e "The argument of ${yellow}\"$1\"${reset} it can not be ${red}\"$2\"${reset}, please, ${yellow}specify a valid one${reset}.\n"
        usage
    fi
}

menu(){
    args_count=0
    only_recon="no"
    only_webapp_enum="no"

    while [ $# -ne 0 ]; do
        (( args_count += 1 ))
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
                    if [[ $(host -t A "$2" | grep -E "has.address" | awk '{print $4}' | grep -E "${IPv4_regex}$" > /dev/null 2>&1; echo $?) -eq 0 ]]; then
                        domain="$2"
                        unset directories_structure
                        directories_structure="domain"
                        shift 2
                    else
                        echo -e "You need specify a valid domain!\n"
                        usage
                    fi
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
            -el|--exclude-domains-list)
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
                if [[ -n "${only_webapp_enum}" ]] && [[ "${only_webapp_enum}" == "yes"  ]]; then
                    echo -e "You can't use this (-re|--recon) option with \"-we|--webapp-enum\"!\n"
                    usage
                fi
                if [[ -n "${url_2_verify}" ]]; then
                    echo -e "With this option (-re|--recon) You can only use \"-d|--domain\"!\n"
                    usage
                fi
                unset only_recon
                only_recon="yes"
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
                        url_2_verify=$2
                        unset directories_structure
                        directories_structure="url"
                        shift 2
                    fi
                fi
                unset status_code
                ;;
            -we|--webapp-enum)
                if [[ -n "${only_recon}" ]] && [[ "${only_recon}" == "yes"  ]]; then
                    echo -e "You can't use this (-we|--webapp-enum) option with \"-re|--recon\"!\n"
                    usage
                fi
                if [[ -n "${url_2_verify}" ]]; then
                    echo -e "You can't use this (-we|--webapp-enum) option with \"-re|--recon\"!\n"
                    usage
                fi
                only_webapp_enum=yes
                shift
                ;;
            -wld|--webapp-long-detection)
                if [ "${#webapp_port_detect[@]}" -eq 0 ]; then
                    webapp_port_detect=("${webapp_port_long_detection[@]}")
                else
                    diff_array=$(diff <(printf "%s\n" "${webapp_port_detect[@]}") <(printf "%s\n" "${webapp_port_long_detection[@]}"))
                    if [[ "${#webapp_port_detect[@]}" -ne 0 ]] && [[ -n ${diff_array} ]]; then
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
            -wtd|--webapp-tool-detection)
                check_argument "$1" "$2"
                webapp_tool_detection="$2"
                shift 2
                ;;
            -ww|--webapp-wordlists)
                check_argument "$1" "$2"
                set -f
                IFS=","
                web_wordlists+=("$2")
                unset IFS
                shift 2
                ;;
            -?*)
                usage
                ;;
            *)
                break
        esac
    done
}
