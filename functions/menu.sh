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

# Validates a domain/hostname string before it is interpolated into URLs
# and filesystem paths. Allows: letters, digits, hyphen, underscore, dot.
# Rejects path separators, shell metacharacters, whitespace, schemes, etc.
# Returns 0 on valid, 1 on invalid (and prints to stderr).
validate_domain(){
    local _candidate="$1"
    if [[ -z "${_candidate}" ]]; then
        echo -e "Empty domain is not allowed." >&2
        return 1
    fi
    if [[ ${#_candidate} -gt 253 ]]; then
        echo -e "Domain is too long (>253 chars): ${_candidate}" >&2
        return 1
    fi
    if ! [[ "${_candidate}" =~ ^[A-Za-z0-9]([A-Za-z0-9_-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9_-]*[A-Za-z0-9])?)*$ ]]; then
        echo -e "Invalid domain format: ${yellow}${_candidate}${reset}" >&2
        return 1
    fi
    return 0
}

check_argument(){
    options+=(-d --domain -dl --domain-list -ed --exclude-domains -el --exclude-domain-list -h --help -k -kill)
    options+=(-kr --kill-remove -l --limit-urls -o --output -p --proxy -r --recon -s --subdomain-brute -u --url)
    options+=(-wc --webapp-crawler -wd --webapp-discovery -we --webapp-enum -ws --webapp-scan)
    options+=(-wld --webapp-long-detection -wsd --webapp-short-detection -ww --webapp-wordlists)
    argument=$2
    if [[ -z "${argument}" ]]; then
        echo -e "The argument of ${yellow}\"$1\"${reset} it can not be ${red}\"empty\"${reset} or you forgot to inform it, please, ${yellow}specify a valid one${reset}.\n"
        usage
    else
        for option in "${options[@]}"; do
            if [[ "${option}" == "${argument}" ]]; then
                echo -e "The argument of ${yellow}\"$1\"${reset} it can not be ${red}\"$2\"${reset}, please, ${yellow}specify a valid one${reset}.\n"
                usage
            fi
        done
    fi
}

menu(){
    args=("$@")
    args_count="$#"
    while [ $# -ne 0 ]; do
        case $1 in
            -d|--domain)
                check_argument "$1" "$2"
                if ! validate_domain "$2"; then
                    usage
                fi
                domain="$2"
                domain_check="yes"
                [[ -n "${domain}" && "${domain_check}" == "yes" ]] && directory_structure="domain"
                shift 2
                ;;
            -dl|--domain-list)
                check_argument "$1" "$2"
                if [ -s "$2" ]; then
                    domain_list=$2
                    domainlist_check="yes"
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
                excludedomain_check="yes"
                shift 2
                ;;
            -el|--exclude-domain-list)
                check_argument "$1" "$2"
                if [ -s "$2" ]; then
                    excludedomain_list="$2"
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
                    kill_check="yes"
                fi
                ;;
            -kr|--kill-remove)
                check_argument "$1" "$2"
                if [ -z "$2" ]; then
                    echo "You need to specify a domain to kill the execution!"
                    exit 1
                else
                    killremove_check="yes"
                fi
                ;;        
            -l|--limit-urls)
                check_argument "$1" "$2"
                if [[ -n "$2" && "$2" == ?(-)+([0-9]) ]]; then
                    limit_urls="$2"
                    limiturls_check="yes"
                    shift 2
                else
                    echo -e "Specify the total number of URLs you want to test!\n"
                    usage
                fi
                ;;
            -o|--output)
                check_argument "$1" "$2"
                output_dir="$2"
                shift 2
                ;;
            -p|--proxy)
                check_argument "$1" "$2"
                use_proxy="yes"
                proxy_ip="$(echo "$2" | sed -E 's/^\s*.*:\/\///g')"
                shift 2
                ;;
            -r|--recon)
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
                        # Append the split element (a single path), not the
                        # raw comma-joined $2. Previous code (`+=("$2")`)
                        # stored the literal "/a.txt,/b.txt" as one array
                        # element (report B-07).
                        dns_wordlists+=("${dw}")
                    else
                        echo -e "${dw} is not a valid file, please enter a valid one.\n"
                        usage
                    fi
                done
                unset IFS
                subdomainbrute_check="yes"
                shift 2
                ;;
            -u|--url)
                check_argument "$1" "$2"
                url_verify="$2"
                url_check="yes"
                [[ -n "${url_verify}" && "${url_check}" == "yes" ]] && directory_structure="url"
                url_domain=$(echo "${url_verify}" | sed -e 's/http.*\/\///' | awk -F'/' '{print $1}' | xargs -I {} basename {})
                shift 2
                ;;
            -wc|--webapp-crawler)
                webapp_crawler_check="yes"
                shift
                ;;
            -wd|--webapp-discovery)
                webapp_discovery_check="yes"
                shift
                ;;
            -we|--webapp-enum)
                webapp_enum_check=yes
                shift
                ;;
            -ws|--webapp-scan)
                webapp_scan_check="yes"
                shift
                ;;
            -wld|--webapp-long-detection)
                webapp_port_detect=("${webapp_port_long_detection[@]}")
                shift
                ;;
            -wsd|--webapp-short-detection)
                webapp_port_detect=("${webapp_port_short_detection[@]}")
                shift
                ;;
            -ww|--webapp-wordlists)
                check_argument "$1" "$2"
                set -f
                IFS=","
                for ww in $2; do
                    if [[ -s "${ww}" ]]; then
                        # Append the split element (single path), not $2
                        # (same bug as -s/--subdomain-brute — report B-07).
                        webapp_wordlists+=("${ww}")
                    else
                        echo -e "${ww} is not a valid file, please enter a valid one.\n"
                        usage
                    fi
                done
                unset IFS
                shift 2
                ;;
            *)
                echo -e "You are specifying the parameter ${yellow}$1${reset}, which is invalid.\n"
                usage
                break
        esac
    done
}
