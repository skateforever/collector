#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * banner                                                #
#   * reset_vars                                            #
#                                                           #
#############################################################            

# Always print the banner
banner(){
echo -e "                                 __ __             __
                    ____ ____   / // /___   ____ _/ /_ ____   ____
                   / __// __ \ / // // _ \ / __//_ __// __ \ / __/ 
                  / /__/ /_/ // // // ___// /__ / /_ / /_/ // /  
                  \___/\____//_//_/ \___/ \___/ \__/ \____//_/   

                                                     by skate4ever
"
}

# Always reset the variables to run the collector
reset_vars(){
    unset directory_structure
    unset domain_check
    unset domainlist_check
    unset excluded_domains
    unset excludedomain_check
    unset excludedomain_list
    unset excludedomainlist_check
    unset kill_check
    unset killremove_check
    unset limit_urls
    unset limiturls_check
    unset output_dir
    unset use_proxy
    unset recon_check
    unset dns_wordlists
    unset subdomainbrute_check
    unset url_check
    unset url_verify
    unset url_domain
    unset webapp_crawler_check
    unset webapp_discovery_check
    unset webapp_enum_check
    unset webapp_scan_check
    unset webapp_port_detect
    unset webapp_wordlists
}

# Replace any occurrence of the configured API keys with a redacted marker.
# Use before writing curl command lines or response bodies to log files,
# so that sharing the log for debugging doesn't leak credentials.
redact_secrets(){
    local _line="$1"
    local _var _val
    for _var in builtwith_api_key censys_api_id censys_api_secret \
                dnsdumpster_api_key hunterio_api lampyre_api_key \
                riskiq_api_key riskiq_api_secret securitytrails_api_key \
                shodan_apikey snov_api_token virustotal_api_key \
                whoisxmlapi_api_key; do
        _val="${!_var}"
        if [[ -n "${_val}" ]]; then
            _line="${_line//${_val}/***REDACTED***}"
        fi
    done
    printf '%s' "${_line}"
}
