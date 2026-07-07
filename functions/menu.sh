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
    local candidate="$1"
    if [[ -z "${candidate}" ]]; then
        echo -e "Empty domain is not allowed." >&2
        return 1
    fi
    if [[ ${#candidate} -gt 253 ]]; then
        echo -e "Domain is too long (>253 chars): ${candidate}" >&2
        return 1
    fi
    if ! [[ "${candidate}" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)*$ ]]; then
        echo -e "Invalid domain format: ${yellow}${candidate}${reset}" >&2
        return 1
    fi
    return 0
}

check_argument(){
    # local arrays — rebuild from scratch on each call (was accumulating across
    # successive invocations because it was global, but the logic never relied
    # on the accumulation).
    local options=()
    options+=(-d --domain -dl --domain-list -ed --exclude-domains -el --exclude-domain-list -h --help)
    options+=(-l --limit-urls -p --proxy -r --recon -ro --report-only -rs --report-stop -s --subdomain-brute -u --url)
    options+=(-vv --vhost-validation -wc --webapp-crawler -wd --webapp-discovery -we --webapp-enum -ws --webapp-scan)
    options+=(-wld --webapp-long-detection -wsd --webapp-short-detection -ww --webapp-wordlists)
    local argument=$2
    local option
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
    local args=("$@")
    args_count="$#"   # GLOBAL — lido por check_parameter_dependency() em check_execution.sh
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
                IFS="," read -ra ed_parts <<< "$2"
                excluded_domains+=("${ed_parts[@]}")
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
            -l|--limit-urls)
                check_argument "$1" "$2"
                if [[ -n "$2" && "$2" =~ ^-?[0-9]+$ ]]; then
                    limit_urls="$2"
                    limiturls_check="yes"
                    shift 2
                else
                    echo -e "Specify the total number of URLs you want to test!\n"
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
                recon_check="yes"
                shift
                ;;
            -vv|--vhost-validation)
                vhost_validation_check="yes"
                shift
                ;;
            -ro|--report-only)
                # Opens the read-only app-report dashboard against the existing
                # outputs/ directory without triggering recon. Handled early
                # in collector (right after menu) so target/lock/validation
                # blocks are skipped entirely.
                report_only_check="yes"
                shift
                ;;
            -rs|--report-stop)
                # Stops a report dashboard previously started with
                # --report-only (foreground gunicorn, pidfile-tracked).
                # Also handled early in collector; no target needed.
                report_stop_check="yes"
                shift
                ;;
            -s|--subdomain-brute)
                check_argument "$1" "$2"
                IFS="," read -ra sb_parts <<< "$2"
                local dw
                for dw in "${sb_parts[@]}"; do
                    if [[ -s "${dw}" ]]; then
                        # Append the split element (a single path), not the
                        # raw comma-joined $2. Previous code (`+=("$2")`)
                        # stored the literal "/a.txt,/b.txt" as one array
                        # element (report B-07).
                        dns_wordlists+=("${dw}")
                    else
                        # Same host-vs-container pitfall as --webapp-wordlists:
                        # the -s test runs inside the container, so a plain
                        # host path (~/foo.txt) or an unmounted path looks
                        # missing here even though it exists on the host.
                        echo -e "${yellow}${dw}${reset} is not a valid file ${red}inside the container${reset}."
                        echo -e "  hint: the path you passed is resolved inside the container, not on the host."
                        echo -e "  Place the wordlist under ${yellow}\${WORDLISTS_DIR}${reset} on the host"
                        echo -e "  (default: ${yellow}<root>/wordlists${reset}, mounted at ${yellow}/opt/collector/wordlists${reset}),"
                        echo -e "  then pass: ${yellow}--subdomain-brute /opt/collector/wordlists/${dw##*/}${reset}"
                        echo -e "  Or set ${yellow}WORDLISTS_DIR=<dir-that-contains-your-file>${reset} when running collector-docker.\n"
                        usage
                    fi
                done
                subdomainbrute_check="yes"
                shift 2
                ;;
            -u|--url)
                check_argument "$1" "$2"
                url_verify="$2"
                url_check="yes"
                [[ -n "${url_verify}" && "${url_check}" == "yes" ]] && directory_structure="url"
                url_domain=$(echo "${url_verify}" | sed -E 's|^https?://||' | awk -F'[/:#?]' '{print $1}')
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
                IFS="," read -ra ww_parts <<< "$2"
                local ww
                for ww in "${ww_parts[@]}"; do
                    if [[ -s "${ww}" ]]; then
                        # Append the split element (single path), not $2
                        # (same bug as -s/--subdomain-brute — report B-07).
                        webapp_wordlists+=("${ww}")
                    else
                        # The path is resolved INSIDE the container. When
                        # the operator passes a host path (e.g. ~/my.txt)
                        # or a plain filename without staging the file
                        # under the wordlists mount, the -s test fails
                        # here even though the file exists on the host.
                        # The old error ('is not a valid file, please
                        # enter a valid one') gave no hint about that
                        # host-vs-container distinction — the new message
                        # spells it out and shows how to fix it.
                        echo -e "${yellow}${ww}${reset} is not a valid file ${red}inside the container${reset}."
                        echo -e "  hint: the path you passed is resolved inside the container, not on the host."
                        echo -e "  Place the wordlist under ${yellow}\${WORDLISTS_DIR}${reset} on the host"
                        echo -e "  (default: ${yellow}<root>/wordlists${reset}, mounted at ${yellow}/opt/collector/wordlists${reset}),"
                        echo -e "  then pass: ${yellow}--webapp-wordlists /opt/collector/wordlists/${ww##*/}${reset}"
                        echo -e "  Or set ${yellow}WORDLISTS_DIR=<dir-that-contains-your-file>${reset} when running collector-docker.\n"
                        usage
                    fi
                done
                shift 2
                ;;
            -dr|--dry-run)
                dry_run_check="yes"
                shift
                ;;
            *)
                echo -e "You are specifying the parameter ${yellow}$1${reset}, which is invalid.\n"
                usage
                break
        esac
    done
}
