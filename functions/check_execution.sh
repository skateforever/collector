#!/bin/bash
#############################################################
# Verify the execution and parameter dependency             #
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * check_execution                                       #
#   * check_parameter_conflicts                             #
#   * check_parameter_dependency                            #
#                                                           #
#############################################################

# Checking if the script has the main parameters needed
check_execution(){
    if [[ ! "${args}" =~ (-d|--domain|-dl|--domain-list|-u|--url) ]]; then
        echo -e "You need at least one option \"-d|--domain\", \"-dl|--domain-list\" OR \"-u|--url\" to execute this script!\n"
        usage
    fi

    if [[ "${args}" =~ (-d|--domain) ]] && [[ "${args}" =~ (-dl|--domain-list|-u|--url) ]]; then
        echo -e "You can not use the option -d|--domain with -dl|--domain-list or -u|--url and vice versa.\n"
        usage
    fi

    if [[ "${args}" =~ (-dl|--domain-list) ]] && [[ "${args}" =~ (-d|--domain|-u|--url) ]]; then
        echo -e "You can not use the option -dl|--domain-list with -d|--domain or -u|--url and vice versa.\n"
        usage
    fi

    if [[ "${args}" =~ (-u|--url) ]] && [[ "${args}" =~ (-d|--domain|-dl|--domain-list) ]]; then
        echo -e "You can not use the option -u|--url with -d|--domain or -dl|--domain-list and vice versa.\n"
        usage
    fi
}

# Checking the runtime parameter dependency for recon
check_parameter_conflicts(){
    # Check Conflicts
    if [[ "${args}" =~ (-e|--exclude-domain) ]] && \
        [[ "${args}" =~ (-el|--exclude-domain-list) ]]; then
        echo "You are trying to use same domain exclusion options, just pick one."
        usage
    fi

    if [[ "${args}" =~ (-k|--kill) ]] && \
        [[ "${args}" =~ (-kr|--kill-remove) ]]; then
        echo "You're trying to use same kill options, just pick one."
        usage
    fi

    if [[ "${args_count}" -gt 1 ]] && [[ "${args}" =~ ( -k | --kill | -kr | --kill-remove ) ]]; then
        echo "You're trying to use kill options and other options, just pick one."
        usage
    fi
}

check_parameter_dependency(){
    # Basic Execution Check
    if  [[ "${args}" =~ (-d|--domain|-dl|--domain-list) ]] && \
        [[ ! -s "${report_dir}/domains_alive.txt" && ! "${args}" =~ (-r|--recon) ]] && \
        [[ ! "${args}" =~ (-wd|--webapp-discovery|-we|--webapp-enum) ]]; then
        echo -e "You are trying to perform recon, but don't have a structure and are using a different parameter than -r|--recon with domain options."
        echo -e "You need to perform at least a basic run to get the subdomain discovered and continue the rest of the activities.\n"
        usage
    fi
    
    # Web Application Discovery Check
    if [[ "${args}" =~ (-wd|--webapp-discovery) ]] && \
        [[ ! -d "${report_dir}" && ! "${args}" =~ (-r|--recon) ]] ; then
        echo -e "You are trying to perform an action where the basic recognition structure does not yet exist; run the collector again with the -r|--recon option.\n"
        usage
    fi

    if [[ "${args}" =~ (-wd|--webapp-discovery) ]] && \
        [[ ! -s "${report_dir}/domain_alive.txt" && ! "${args}" =~ (-r|--recon) ]] ; then
        echo -e "You are trying to run web application discovery without having previously run recon, use the -r|--recon option and run again.\n"
        usage
    fi
    
    if [[ "${args}" =~ (-wd|--webapp-discovery) ]] && \
        [[ ! "${args}" =~ (-wld|--webapp-long-detaction|-wsd|--webapp-short-detection) ]]; then
        echo -e "You are trying to find out which web applications are active, but forgot to specify which ports to test."
        echo -e "Choose one of the options (-wld|--webapp-long-detection or -wsd|--webapp-short-detection) and run again.\n"
        usage
    fi

    if [[ "${args}" =~ (-wld|--webapp-long-detaction|-wsd|--webapp-short-detection)  ]] && \
        [[ ! "${args}" =~ (-wd|--webapp-discovery) ]]; then
        echo -e "You trying to execute collector with web app discovery without at least one valid option to port detection.\n"
        usage
    fi

    # Web Application Enumeration Check
    if [[ "${args}" =~ (-we|--webapp-enum) ]] && \
        [[ ! -s "${report_dir}" && ! "${args}" =~ (-r|--recon) ]] ; then
        echo -e "You are trying to perform an action where the basic recognition structure does not yet exist; run the collector again with the -r|--recon option.\n"
        usage
    fi

    if [[ "${args}" =~ (-we|--webapp-enum) ]] && \
        [[ ! -s "${report_dir}/domain_alive.txt" && ! "${args}" =~ (-r|--recon) ]] ; then
        echo -e "You are trying to run web application discovery without having previously run recon, use the -r|--recon option and run again.\n"
        usage
    fi

    if [[ "${only_webapp_enum}" == "yes" ]] && \
        [[ ! "${args}" =~ (-wd|--webapp-discovery) && ! -s "${report_dir}/webapp_urls.txt" ]]; then
        echo -e "Make sure the ${yellow}webapp_urls.txt${reset} exist and isn't empty, or really, we have a problem with script execution."
        echo -e "Try running the script with the -wd|--webapp-discovery option and run again.\n"
        usage
    fi

    if [[ "${only_webapp_enum}" == "yes" ]] && [[ ${#webapp_wordlists[@]} -eq 0 ]]; then
        echo -e "Please, ${yellow}make sure${reset} you have at least one wordlist to web directory and file discovery!\n"
        usage
    fi

    if [[ -n "${url_2_verify}" ]]; then
        echo -e "You can't use this (-we|--webapp-enum) option with \"-u|--url\"!\n"
        usage
    fi

    # Full Execution Check

    # URL
    if [[ -n "${url_2_verify}" ]] && [[ -z "${domain}" ]] && [[ ! -s "${domain_list}" ]]; then
        if [[ "${args_count}" -gt 4 ]]; then
            echo -e "You are trying to pass a number of parameters beyond what is necessary for this collector reconnaissance option \"${yellow}-u|--url${reset}\".\n"
            usage
        fi
    fi
    if [[ -n "${url_2_verify}" ]] && [[ -z "${domain}" ]] && [[ ! -s "${domain_list}" ]]; then
        if [[ "${args_count}" -gt 4 ]] && [[ ! "${args}" =~ (-ww|--webapp-wordlist) ]]; then
            echo -e "Maybe you forget the -ww|--webapp-wordlist option to use with reconnaissance option \"${yellow}-u|--url${reset}\".\n"
            usage
        fi
    fi
}
