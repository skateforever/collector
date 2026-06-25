#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * vhost-probe-src                                       #
#                                                           #
#############################################################
#
# Note: this source is complementary to vhost_check() in
# functions/infra.sh. While vhost_check() probes unresolved
# subdomains (domains_without_resolution) against live IPs
# discovered during full recon, vhost-probe-src runs early
# (during subdomains_recon) against the root domain's own
# IP addresses, using a wordlist of common vhost names to
# discover hidden virtual hosts before the full recon cycle.
#
#############################################################

vhost-probe-src(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing vhost probe... "
    : > "${tmp_dir}/vhost_probe_output.txt"
    unset user_agent
    user_agent="$(get_user_agent)"
    local vhost_probe_words=(
        dev dev1 dev2 dev3 development staging stage stg stg1
        test test1 test2 testing qa qa1 qa2 uat sit
        preprod pre-prod pre rc sandbox playground lab labs
        demo preview beta alpha canary
        prod production live www web app apps
        api api2 apiv2 v1 v2
        cdn static assets media img images
        files uploads download downloads s3 storage
        admin administrator admin1 panel control
        dashboard cp cpanel whm plesk
        mgmt management manage manager
        portal console ui gui
        internal intranet corp corporate private
        vpn remote gateway proxy firewall fw
        ns ns1 ns2 dns mx smtp
        mail mail1 mail2 webmail imap pop exchange
        jenkins ci cd build deploy deployment
        git gitlab github bitbucket svn repo
        registry docker k8s kubernetes rancher
        vault consul terraform
        monitor monitoring grafana kibana prometheus
        elk logstash splunk alert alerts status uptime health
        auth sso login oauth oidc idp identity accounts
        support help helpdesk ticket tickets jira
        docs doc wiki kb forum community chat feedback
        backend frontend service services svc
        rpc graphql ws websocket
        db database search elastic
        analytics metrics stats tracking
        shop store checkout payment pay
    )
    # Resolve target IPs
    local vhost_probe_ips
    vhost_probe_ips="$(dig +short A "${domain}" 2>/dev/null | grep -Eo "${IPv4_regex}" | head -3)"
    if [[ -z "${vhost_probe_ips}" ]]; then
        echo "Done!"
        return 0
    fi
    # Establish baseline response (root domain on first IP)
    local vhost_probe_first_ip
    vhost_probe_first_ip="$(echo "${vhost_probe_ips}" | head -1)"
    local vhost_probe_baseline_status=""
    local vhost_probe_baseline_len=0
    echo -e "\ncurl ${curl_options_fast[@]} -H \"Host: ${domain}\" -H \"User-agent: ${user_agent}\" -o /dev/null -w \"%{http_code} %{size_download}\" \"http://${vhost_probe_first_ip}\"" >> "${log_execution_file}"
    local vhost_probe_baseline_raw
    vhost_probe_baseline_raw="$(curl "${curl_options_fast[@]}" \
        -H "Host: ${domain}" \
        -H "User-agent: ${user_agent}" \
        -o /dev/null -w "%{http_code} %{size_download}" \
        "http://${vhost_probe_first_ip}" 2>/dev/null)"
    vhost_probe_baseline_status="$(echo "${vhost_probe_baseline_raw}" | awk '{print $1}')"
    vhost_probe_baseline_len="$(echo "${vhost_probe_baseline_raw}" | awk '{print $2}')"
    [[ -z "${vhost_probe_baseline_len}" ]] && vhost_probe_baseline_len=0
    # Probe each (IP, word) pair
    while IFS= read -r vhost_probe_ip; do
        [[ -z "${vhost_probe_ip}" ]] && continue
        for vhost_probe_word in "${vhost_probe_words[@]}"; do
            local vhost_probe_host="${vhost_probe_word}.${domain}"
            echo -e "\ncurl ${curl_options_fast[@]} -H \"Host: ${vhost_probe_host}\" -H \"User-agent: ${user_agent}\" -o /dev/null -w \"%{http_code} %{size_download}\" \"http://${vhost_probe_ip}\"" >> "${log_execution_file}"
            local vhost_probe_raw
            vhost_probe_raw="$(curl "${curl_options_fast[@]}" \
                -H "Host: ${vhost_probe_host}" \
                -H "User-agent: ${user_agent}" \
                -o /dev/null -w "%{http_code} %{size_download}" \
                "http://${vhost_probe_ip}" 2>/dev/null)"
            local vhost_probe_status
            local vhost_probe_len
            vhost_probe_status="$(echo "${vhost_probe_raw}" | awk '{print $1}')"
            vhost_probe_len="$(echo "${vhost_probe_raw}" | awk '{print $2}')"
            [[ -z "${vhost_probe_len}" ]] && vhost_probe_len=0
            local vhost_probe_diff=$(( vhost_probe_len - vhost_probe_baseline_len ))
            [[ "${vhost_probe_diff}" -lt 0 ]] && vhost_probe_diff=$(( vhost_probe_diff * -1 ))
            if [[ "${vhost_probe_status}" != "${vhost_probe_baseline_status}" || "${vhost_probe_diff}" -gt 200 ]]; then
                echo -e "\nvhost hit: ${vhost_probe_host} on ${vhost_probe_ip} (${vhost_probe_status}, ${vhost_probe_len}B)" >> "${log_execution_file}"
                echo "${vhost_probe_host}" >> "${tmp_dir}/vhost_probe_output.txt"
            fi
        done
    done <<< "${vhost_probe_ips}"
    sort -u -o "${tmp_dir}/vhost_probe_output.txt" "${tmp_dir}/vhost_probe_output.txt" 2>/dev/null
    echo "Done!"
}

vhost-probe-src
