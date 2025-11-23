#!/bin/bash
#############################################################
# This function try to seek for vhost subdomains            #
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * vhost_check                                           #
#                                                           #
#############################################################            

# Starting with HTTP 1.1, the server takes the header into 
# account to internally route to which site it should respond 
# to, and if the server is prepared to respond for that host, 
# it will do so. To verify if the hosts we're not getting a 
# response from are actually offline, we can use the client 
# (curl or httpx) to search for the IPs we know.

# There are two ways to do this:
# curl -k -H 'Host: www.abc.com' https://32.21.169.52
# curl -k --resolve www.abc.com:443:32.21.169.52 https://www.abc.com

# In the first way The TCP connection will occur to IP regardless 
# of DNS resolution, however, the HTTP header will send the host www.abc.com. 
# Therefore, we will obtain the same response result.

# However, in this way we can change the IP address to any other, and if 
# the server at this IP exists and is prepared to respond to the website 
# www.abc.com, the response (HTTP Status code and size) will be the same.

# However, in this scenario, the Subject Name provided via SNI will 
# be the IP address instead of the hostname. Therefore, in scenarios 
# where TLS requires SNI, this approach may not work.

# In the second way Therefore, we use the second approach which, similarly 
# to the first method, necessarily establishes a TCP connection to the 
# IP address because the `--resolve` parameter ignores name resolution 
# via DNS. The Host header and the Subject Name of the SNI will necessarily 
# be correctly defined.

# Thus, we can use this technique and pass a list of IP addresses and 
# check if they are configured to respond for a specific website.

# In this way, discovering possible vhosts

# Pro Tips:
# Use multiple techniques: Combine vhost discovery with DNS enumeration
# Try different protocols: HTTP vs HTTPS might reveal different results
# Check for header injection: Add X-Forwarded-Host and other headers
# Use auto-calibration: Helps filter out common false positives
# Look for subtle differences: Even small size/word count differences can indicate valid vhosts

vhost_check(){
    echo -n "Looking for vhost with dead subdomains... "
    if [[ -s "${report_dir}/domains_external_ipv4.txt" && -s "${report_dir}/domains_without_resolution.txt" ]]; then
        for subdomain in $(cat "${report_dir}/domains_without_resolution.txt"); do
            for IP in $(awk '{print $2}' "${report_dir}/domains_external_ipv4.txt" | sort -u); do
                curl "${curl_options[@]}" --resolve "${subdomain}":80:"${IP}" http://"${subdomain}"
                curl "${curl_options[@]}" --resolve "${subdomain}":443:"${IP}" https://"${subdomain}"
            done
        done
        gobuster vhost -u https://example.com -w /path/to/wordlist.txt
        webfinder -t https://x.com/ -ip tst.txt -o x.txt --random-agent
    fi
    

# Basic vhost discovery with a wordlist
ffuf -w subdomains.txt -u https://TARGET -H "Host: FUZZ.TARGET" -mc all

# With common response code filtering
ffuf -w subdomains.txt -u https://TARGET -H "Host: FUZZ.TARGET" -mc 200,204,301,302,307,401,403,405

# Using IP address instead of domain (bypasses some load balancers)
ffuf -w subdomains.txt -u http://TARGET_IP -H "Host: FUZZ.TARGET" -mc all

# With auto-calibration to filter out false positives
ffuf -w subdomains.txt -u https://TARGET -H "Host: FUZZ.TARGET" -ac -mc all

# Multiple host header techniques
ffuf -w subdomains.txt -u https://TARGET -H "Host: FUZZ.TARGET" -H "X-Forwarded-Host: FUZZ.TARGET" -mc all

# With size and word count filtering to find subtle differences
ffuf -w subdomains.txt -u https://TARGET -H "Host: FUZZ.TARGET" -mc all -fs 0 -fw 0

ffuf -w subdomains.txt -u https://target.com \
    -H "Host: FUZZ.target.com" \
    -ac \
    -mc 200,204,301,302,307,401,403,405,500 \
    -o vhost_results.txt \
    -of json \
    -v


        vhost_original="$(timeout --signal=9 1 curl -siLk -o /dev/null -w "%{response_code}","%{size_download}" "$IP" --no-keepalive)"


    if [[ -s "${report_dir}/domains_without_resolution.txt" ]] && [[ -s "${report_dir}/domains_external_ipv4.txt" ]]; then
        # Getting the IPs
        for IP in $(awk '{print $2}' "${report_dir}/domains_external_ipv4.txt" | sort -u) ; do
            #Getting the ports
            for PORT in ${web_port_detect[@]}; do
                # Getting the dead subdomains
                while read DEAD_SUBDOMAIN; do
                    #vhost_hostheader_check="$(timeout --signal=9 5 curl -siLk -o /dev/null -w "%{response_code}","%{size_download}" http://"${IP}" -H Host:"${DEAD_UBDOMAIN}")"
                    vhost_dns_check="$(timeout --signal=9 8 curl -sikL "${DEAD_SUBDOMAIN}" --resolve "${DEAD_SUBDOMAIN}:${PORT}:${IP}" -o /dev/null -w "%{response_code}","%{size_download}")"
                done < "${report_dir}/domains_without_resolution.txt"
            done
        done
    fi

    echo "Done!"
    #echo "The error occurred in the function emails_recon.sh!" | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
    #echo -e "The message was: \n\tMake sure the directories structure was created. Stopping the script." |
    #echo "The reconnaissance for ${domain} failed at $(date +"%Y%m%d %H:%M")" | notify -nc -silent -id "${notify_recon_channel}" > /dev/null

}
