#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * srv-enum-src                                          #
#                                                           #
#############################################################

srv-enum-src(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing SRV enum... "
    : > "${tmp_dir}/srv_enum_output.txt"
    srv_prefixes=(
        _http._tcp _https._tcp _ftp._tcp _sftp._tcp _ssh._tcp _smtp._tcp
        _submission._tcp _smtps._tcp _pop3._tcp _pop3s._tcp _imap._tcp _imaps._tcp
        _ldap._tcp _ldaps._tcp _kerberos._tcp _kerberos._udp _kpasswd._tcp
        _sip._tcp _sip._udp _sips._tcp _xmpp-client._tcp _xmpp-server._tcp
        _autodiscover._tcp _caldav._tcp _caldavs._tcp _carddav._tcp _carddavs._tcp
        _vpn._tcp _pptp._tcp _l2tp._udp _ipsec-nat-t._udp
        _msrpc._tcp _ms-wbt-server._tcp _telnets._tcp
        _ntp._udp _snmp._udp _radius._udp _diameter._tcp
        _git._tcp _svn._tcp _jenkins._tcp _docker._tcp
        _mongodb._tcp _redis._tcp _elasticsearch._tcp _kafka._tcp _zookeeper._tcp
    )
    for srv_prefix in "${srv_prefixes[@]}"; do
        echo -e "\ndig +short SRV \"${srv_prefix}.${domain}\"" >> "${log_execution_file}"
        srv_result="$(dig +short SRV "${srv_prefix}.${domain}" 2>/dev/null)"
        if [[ -n "${srv_result}" ]]; then
            echo "${srv_result}" | awk '{print $4}' | sed 's/\.$//' | tr '[:upper:]' '[:lower:]' >> "${tmp_dir}/srv_enum_output.txt"
        fi
    done
    sort -u -o "${tmp_dir}/srv_enum_output.txt" "${tmp_dir}/srv_enum_output.txt" 2>/dev/null
    echo "Done!"
}

srv-enum-src
