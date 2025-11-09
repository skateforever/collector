#!/bin/bash
#############################################################
# Verify the execution and parameter dependency             #
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * check_execution                                       #
#   * check_parameter_dependency_domain                     #
#   * check_is_know_target                                  #
#                                                           #
#############################################################

# Checking if the script has the main parameters needed
check_execution(){
    if [[ ! "$@" =~ ( -d | --domain | -dl | --domain-list | -u | --url ) ]]; then
        echo -e "You need at least one option \"-d|--domain\", \"-dl|--domain-list\" OR \"-u|--url\" to execute this script!\n"
        usage
    fi

    if [[ "$@" =~ ( -d | --domain ) ]] && [[ "$@" =~ ( -dl | --domain-list | -u | --url ) ]]; then
        echo "You can not use the option -d|--domain with -dl|--domain-list and vice versa."
        usage
    fi

    #if [[ "$@" =~ ( -u | --url ) ]] && [[ "$@" =~ ( -d | --domain ) ]]; then
    #    echo "You can not use the option -u|--url with -d|--domain and vice versa."
    #    usage
    #fi

    #if [[ "$@" =~ ( -u | --url ) ]] && [[ "$@" =~ ( -dl | --domain-list ) ]]; then
    #    echo "You can not use the option -u|--url with -dl|--domain-list and vice versa."
    #    usage
    #fi
}

# Checking the runtime parameter dependency for recon
check_parameter_dependency_domain(){
    # Domain
    if [[ -n "${domain}" ]] || [[ -s "${domain_list}" ]] && [[ -z "${url_2_verify}" ]]; then
        if [[ "${args_count}" -gt 9 ]]; then 
            echo -e "You are trying to pass a number of parameters beyond what is necessary for this collector reconnaissance option \"${yellow}-d|--domain${reset}\".\n"
            usage
        fi
    fi

    if [[ "$@" =~ ( -wd | --webapp-discovery ) ]] && \
        [[ ! "$@" =~ ( -d | --domain | -dl | --domain-list | -we | --webapp-enum )  ]]; then
        echo "You trying to use web app discovery without at least one valid option (domain or web app enum)."
        usage
    fi

    if [[ "$@" =~ ( -wd | --webapp-discovery ) ]] && \
        [[ ! "$@" =~ ( -wld | --webapp-long-detaction | -wsd | --webapp-short-detection )  ]]; then
        echo "You trying to use web app discovery without at least one valid option to port detection."
        usage
    fi

    if [[ "$@" =~ ( -wld | --webapp-long-detaction | -wsd | --webapp-short-detection )  ]] && \
        [[ ! "$@" =~ ( -wd | --webapp-discovery ) ]]; then
        echo "You trying to use web app discovery without at least one valid option to port detection."
        usage
    fi

    if [[ "$@" =~ ( -we | --webapp-enum ) ]] && \
        [[ ! "$@" =~ ( -wd | --webapp-discovery )  ]] && \
        [[ ! -s "${report_dir}/webapp_urls.txt" ]]; then
        echo "You probably forgot to add ${yellow}--webapp-discovery${reset} option to execute and validate what web app are runnning on ${domain}."
        usage
    fi

    if [[ "${only_webapp_enum}" == "yes" ]] && [[ ! -s "${report_dir}/webapp_urls.txt" ]]; then
        echo "Make sure the ${red}${report_dir}/webapp_urls.txt${reset} exist and isn't empty, or really, we have a problem with script execution."
        usage
    fi

    if [[ "${only_webapp_enum}" == "yes" ]] && [[ ${#webapp_wordlists[@]} -eq 0 ]]; then
        echo -e "Please, ${yellow}make sure${reset} you have at least one wordlist to web directory and file discovery!\n"
        usage
    fi

    # URL
    if [[ -n "${url_2_verify}" ]] && [[ -z "${domain}" ]] && [[ ! -s "${domain_list}" ]]; then
        if [[ "${args_count}" -gt 4 ]]; then
            echo -e "You are trying to pass a number of parameters beyond what is necessary for this collector reconnaissance option \"${yellow}-u|--url${reset}\".\n"
            usage
        fi
    fi
}

# Checking if is a know target to get the cursor position
check_is_known_target(){
    if [[ -n "$1" ]] && [[ -d "${output_dir}/$1" ]]; then
        echo "This is a known target."
    fi
}
