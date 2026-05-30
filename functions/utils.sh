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

# Scan downloaded JavaScript files for likely API keys, tokens, secrets and
# other credentials. Designed to run after crawler_js, so the input is already
# scoped to the target's own code (the crawler filters by domain before
# downloading). Each hit is written as one line:
#
#     <label>:<file>:<line>:<match>
#
# Args:
#   $1 - directory to scan recursively (default: ${webapp_js_dir})
#   $2 - output file              (default: ${report_dir}/webapp_js_secrets.txt)
scan_js_secrets(){
    local scan_dir="${1:-${webapp_js_dir}}"
    local out_file="${2:-${report_dir}/webapp_js_secrets.txt}"
    local label regex hits line total i
    local channel="${notify_high_channel:-${notify_recon_channel}}"

    [[ ! -d "${scan_dir}" ]] && return 0

    # Alternating pairs: label, regex (ERE). Matched case-insensitively. Order
    # matters — narrower / higher-signal patterns first so the report is
    # easier to triage.
    local -a patterns=(
        "AWS_ACCESS_KEY"        'AKIA[0-9A-Z]{16}'
        "AWS_SESSION_TOKEN"     'ASIA[0-9A-Z]{16}'
        "GCP_API_KEY"           'AIza[0-9A-Za-z_\-]{35}'
        "GITHUB_TOKEN"          'gh[pousr]_[A-Za-z0-9]{36,255}'
        "GITLAB_TOKEN"          'glpat-[A-Za-z0-9_\-]{20,}'
        "SLACK_TOKEN"           'xox[baprsu]-[A-Za-z0-9-]{10,72}'
        "SLACK_WEBHOOK"         'https://hooks\.slack\.com/services/T[A-Za-z0-9]+/B[A-Za-z0-9]+/[A-Za-z0-9]+'
        "STRIPE_LIVE_SECRET"    'sk_live_[0-9a-zA-Z]{24,}'
        "STRIPE_TEST_SECRET"    'sk_test_[0-9a-zA-Z]{24,}'
        "STRIPE_PUBLISHABLE"    'pk_live_[0-9a-zA-Z]{24,}'
        "MAILGUN_KEY"           'key-[0-9a-zA-Z]{32}'
        "SENDGRID_KEY"          'SG\.[A-Za-z0-9_\-]{22}\.[A-Za-z0-9_\-]{43}'
        "TWILIO_SID"            'AC[a-f0-9]{32}'
        "TWILIO_AUTH"           '[Tt]wilio.{0,20}[A-Fa-f0-9]{32}'
        "HEROKU_KEY"            '[Hh]eroku.{0,20}[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
        "JWT"                   'eyJ[A-Za-z0-9_\-]{10,}\.eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}'
        "FIREBASE_DB"           'https?://[a-z0-9-]+\.firebaseio\.com'
        "GOOGLE_OAUTH_ID"       '[0-9]+-[0-9a-z_]{32}\.apps\.googleusercontent\.com'
        "PRIVATE_KEY"           '-----BEGIN [A-Z ]*PRIVATE KEY-----'
        "BEARER_HEADER"         'Bearer[[:space:]]+[A-Za-z0-9._\-]{20,}'
        "BASIC_AUTH_URL"        'https?://[A-Za-z0-9._%+-]+:[^@[:space:]/"]{4,}@'
        "GENERIC_API_KEY"       '(api[_-]?key|apikey|access[_-]?token|auth[_-]?token|secret[_-]?key|client[_-]?secret|x-api-key)[[:space:]]*[:=][[:space:]]*["'\''][A-Za-z0-9_\-]{16,}["'\'']'
    )

    : > "${out_file}"
    {
        echo "# JS secret-scan report for ${domain}"
        echo "# scan_dir: ${scan_dir}"
        echo "# date: $(date +"%Y-%m-%d %H:%M:%S")"
        echo "# format: <label>:<file>:<line>:<match>"
        echo
    } >> "${out_file}"

    total=0
    for ((i=0; i<${#patterns[@]}; i+=2)); do
        label="${patterns[i]}"
        regex="${patterns[i+1]}"
        hits="$(grep -rEHnIoi --include='*.js' "${regex}" "${scan_dir}" 2>/dev/null)"
        [[ -z "${hits}" ]] && continue
        while IFS= read -r line; do
            # Strip our own configured API keys from the output so the report
            # never echoes back the operator's own credentials.
            line="$(redact_secrets "${line}")"
            printf '%s:%s\n' "${label}" "${line}" >> "${out_file}"
            total=$((total+1))
        done <<< "${hits}"
    done

    if [[ "${total}" -gt 0 ]]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} JS secrets: ${total} candidate(s) flagged → ${out_file}"
        {
            echo "JS secret candidates for ${domain}: ${total}"
            echo "Report: ${out_file}"
            echo
            grep -v '^#' "${out_file}" | grep -v '^$' | head -n 30
            [[ "${total}" -gt 30 ]] && echo "... ($((total - 30)) more)"
        } | notify -nc -silent -id "${channel}" > /dev/null 2>&1
    fi
}

# Scan downloaded JavaScript files for parameter names and DOM/JS sinks that
# commonly mark injection-prone code paths. The goal isn't to prove a bug —
# it's to give the operator a starting list of "places worth poking at"
# during manual testing.
#
# For each pattern category (SQLi, XSS, SSRF, XXE, CMD, OPEN_REDIRECT, PATH,
# DOM_SINK, EVAL_SINK, POSTMSG, CRYPTO_WEAK) the function emits hits in:
#
#     <category>:<file>:<line>:<match>
#
# Categories are intentionally broad: a hit means "this name or sink appears
# in the code", not "this is exploitable". Triage in the manual phase.
#
# Args:
#   $1 - directory to scan recursively (default: ${webapp_js_dir})
#   $2 - output file              (default: ${report_dir}/webapp_js_params.txt)
scan_js_params(){
    local scan_dir="${1:-${webapp_js_dir}}"
    local out_file="${2:-${report_dir}/webapp_js_params.txt}"
    local label regex hits line total i
    local channel="${notify_recon_channel}"

    [[ ! -d "${scan_dir}" ]] && return 0

    # Two layers of patterns:
    #   1. Param-name patterns — fire when a sensitive parameter NAME appears
    #      (`?id=`, `&redirect=`, `userInput`, request.body.url, etc.).
    #   2. Sink patterns — fire when JS reaches a dangerous DOM/JS API
    #      regardless of where the data came from.
    #
    # `\b` is GNU-grep specific; the patterns below stick to portable ERE so
    # they also work on macOS BSD grep.
    local -a patterns=(
        # ---- SQLi-flavored param names commonly reflected in queries ----
        "SQLi"           '[?&"'\'']((id|uid|user_?id|account_?id|order_?id|product_?id|item_?id|cat|category|sort|order|filter|search|q|query|sql|where|select|table|column|page|per_?page|limit|offset)=|\.(id|userId|accountId|orderId)[[:space:]]*[=:])'

        # ---- XSS sources / sinks ----
        "XSS_SOURCE"     '(location\.(search|hash|href|pathname)|document\.(URL|documentURI|baseURI|referrer|cookie)|window\.name|history\.(state|pushState|replaceState))'
        "XSS_SINK"       '(\.innerHTML|\.outerHTML|document\.write(ln)?|\.insertAdjacentHTML|\$\([^)]*\)\.html\(|\.setAttribute\([[:space:]]*["'\''](src|href|action|formaction|data|on[a-z]+)["'\'']|\.srcdoc|element\.html\()'

        # ---- SSRF-shaped param names + URL-fetching sinks ----
        "SSRF_PARAM"     '[?&"'\'']((url|uri|next|redirect|redirect_?uri|return|return_?url|callback|callback_?url|continue|dest|destination|target|target_?url|to|forward|forward_?url|fetch|fetch_?url|webhook|proxy|proxy_?url|src|source|image|img|avatar|file|filename|path|page|domain|host|hostname|address|api|api_?url|endpoint)=)'
        "SSRF_SINK"      '(fetch[[:space:]]*\(|new[[:space:]]+XMLHttpRequest|\.open[[:space:]]*\([[:space:]]*["'\''](GET|POST|PUT|DELETE|PATCH)["'\'']|axios\.(get|post|put|delete|patch|request)|\$\.(ajax|get|post)|navigator\.sendBeacon|EventSource\(|new[[:space:]]+WebSocket\()'

        # ---- Open redirect sinks ----
        "OPEN_REDIRECT"  '(location[[:space:]]*=|location\.(href|assign|replace)[[:space:]]*=?[[:space:]]*\(?|window\.open[[:space:]]*\()'

        # ---- XXE / XML parsers reachable from JS ----
        "XXE"            '(DOMParser\(\)\.parseFromString|new[[:space:]]+DOMParser\(\)|loadXML[[:space:]]*\(|XMLHttpRequest.*responseXML|libxmljs|fast-xml-parser|xml2js)'

        # ---- Command-injection / server-side template flavored names ----
        "CMD_PARAM"      '[?&"'\'']((cmd|command|exec|run|do|action|task|operation|shell|ip|host|ping|domain|name|file|filename)=|`[^`]*\$\{)'
        "CMD_SINK"       '(child_process\.(exec|execSync|spawn|spawnSync|fork)|require\(["'\'']child_process|process\.exec|new[[:space:]]+Function\(|eval[[:space:]]*\()'

        # ---- Path-traversal flavored names + Node fs sinks ----
        "PATH_PARAM"     '[?&"'\'']((file|filepath|path|dir|folder|root|template|include|require|load|page|view|theme|module|locale)=)'
        "PATH_SINK"      '(fs\.(readFile|readFileSync|createReadStream|writeFile|writeFileSync|unlink|unlinkSync|stat|lstat|access|exists)|require\([[:space:]]*[a-zA-Z_$])'

        # ---- DOM clobbering / DOM-XSS specific ----
        "DOM_SINK"       '(eval[[:space:]]*\(|setTimeout[[:space:]]*\([[:space:]]*["'\''`]|setInterval[[:space:]]*\([[:space:]]*["'\''`]|new[[:space:]]+Function\(|Function[[:space:]]*\([[:space:]]*["'\''`])'

        # ---- postMessage handlers without origin checks ----
        "POSTMSG"        '(addEventListener[[:space:]]*\([[:space:]]*["'\'']message["'\'']|window\.onmessage[[:space:]]*=)'

        # ---- Weak crypto / homegrown auth ----
        "CRYPTO_WEAK"    '(\.createHash\([[:space:]]*["'\''](md5|sha1)["'\'']|CryptoJS\.(MD5|SHA1)|Math\.random\([[:space:]]*\)[[:space:]]*\.toString)'

        # ---- Prototype pollution sinks ----
        "PROTO_POLLUTION" '(__proto__|constructor\.prototype|Object\.assign\([[:space:]]*[a-zA-Z_$])'

        # ---- Hardcoded internal hosts that often hint at SSRF reach ----
        "INTERNAL_HOST"  '(localhost|127\.0\.0\.1|169\.254\.169\.254|metadata\.google\.internal|\.consul|\.svc\.cluster\.local|10\.[0-9]+\.[0-9]+\.[0-9]+|192\.168\.[0-9]+\.[0-9]+|172\.(1[6-9]|2[0-9]|3[0-1])\.[0-9]+\.[0-9]+)'
    )

    : > "${out_file}"
    {
        echo "# JS param/sink scan report for ${domain}"
        echo "# scan_dir: ${scan_dir}"
        echo "# date: $(date +"%Y-%m-%d %H:%M:%S")"
        echo "# format: <category>:<file>:<line>:<match>"
        echo "# NOTE: a hit means \"worth a manual look\", not \"vulnerable\"."
        echo
    } >> "${out_file}"

    total=0
    for ((i=0; i<${#patterns[@]}; i+=2)); do
        label="${patterns[i]}"
        regex="${patterns[i+1]}"
        hits="$(grep -rEHnIoi --include='*.js' "${regex}" "${scan_dir}" 2>/dev/null)"
        [[ -z "${hits}" ]] && continue
        while IFS= read -r line; do
            line="$(redact_secrets "${line}")"
            printf '%s:%s\n' "${label}" "${line}" >> "${out_file}"
            total=$((total+1))
        done <<< "${hits}"
    done

    if [[ "${total}" -gt 0 ]]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} JS sinks: ${total} candidate(s) flagged → ${out_file}"
        {
            echo "JS injection-sink candidates for ${domain}: ${total}"
            echo "Report: ${out_file}"
            echo
            echo "Per-category counts:"
            grep -v '^#' "${out_file}" | grep -v '^$' | awk -F: '{print $1}' | sort | uniq -c | sort -rn
            echo
            echo "Top hits:"
            grep -v '^#' "${out_file}" | grep -v '^$' | head -n 30
            [[ "${total}" -gt 30 ]] && echo "... ($((total - 30)) more)"
        } | notify -nc -silent -id "${channel}" > /dev/null 2>&1
    fi
}
