#!/bin/bash
#############################################################
#                                                           #
# JavaScript static-scan helpers.                           #
#                                                           #
# All functions consume files downloaded by the crawler     #
# (crawler_js). scan_js_secrets and scan_js_params grep them #
# against a pattern set from conf.d/operation.conf, and     #
# emit tagged findings in the standard format:               #
#                                                           #
#     <label|category>:<file>:<line>:<match>                #
#                                                           #
# Findings are notified via the notify pipeline. scan_js_secrets and         #
# scan_js_params never mutate the JS files themselves.        #
#                                                           #
# beautify_js_files and deobfuscate_js_files run first, and    #
# between them a downloaded <name>.js goes through TWO          #
# on-disk states before scanning:                                #
#                                                           #
#   1. beautify_js_files MOVES <name>.js to <name>.beautify.js  #
#      (pretty-printed by js-beautify) — <name>.js no longer     #
#      exists on disk at this point. This copy is kept           #
#      permanently as an audit artifact: the downloaded code,     #
#      still minified/obfuscated, just readable.                  #
#   2. deobfuscate_js_files reads <name>.beautify.js and          #
#      CREATES <name>.js from scratch with js_deobfuscator.py's   #
#      (support/runtime/scripts/) result, reversing hex/unicode   #
#      string escapes, base64-in-atob, the Dean Edwards packer    #
#      and javascript-obfuscator's string-array encoding so        #
#      literal values — including hardcoded secrets — come back   #
#      as plain strings. If the file wasn't actually obfuscated   #
#      (no technique applied), <name>.js is a plain byte-for-byte  #
#      copy of <name>.beautify.js instead — see deobfuscate_js_files#
#      for why. <name>.beautify.js itself is never modified by     #
#      this step. <name>.js is the file scan_js_secrets /          #
#      scan_js_params below actually scan.                         #
#                                                           #
# If beautify_js_files was skipped or failed for a given file     #
# (js-beautify missing, or it errored on that file), <name>.js     #
# never got moved away — deobfuscate_js_files then reads/writes    #
# that same <name>.js path directly (see its own comment).         #
# If deobfuscate_js_files itself can't run at all (python3/jq      #
# missing, or the script is missing), it still promotes every      #
# <name>.beautify.js into <name>.js via a plain copy, so the       #
# scans below always have a <name>.js to read — without this,      #
# beautify's move would otherwise leave the file invisible to      #
# them (they deliberately exclude *.beautify.js).                   #
#                                                           #
# Both scans below exclude *.beautify.js from their grep so a     #
# secret restored by deobfuscate_js_files is counted once, from    #
# <name>.js, not twice. Without the deobfuscate step, a secret      #
# hidden inside an obfuscator's string array (e.g. decoder(0x1a2)  #
# instead of the literal "sk_live_...") would never surface to      #
# scan_js_secrets below.                                             #
#                                                           #
# Exposes:                                                  #
#   * beautify_js_files    (move downloaded JS into <name>.beautify.js)
#   * deobfuscate_js_files (detect + reverse JS obfuscation, creating <name>.js)
#   * scan_js_secrets      (API keys / tokens / credentials)
#   * scan_js_params       (parameter names + injection sinks)
#                                                           #
#############################################################

# Pretty-print every downloaded .js file and MOVE it to a sibling
# <name>.beautify.js — <name>.js no longer exists after this (deobfuscate_js_files
# creates it fresh from the beautified copy). The .beautify.js copy is a
# permanent audit artifact (pretty but still minified/obfuscated) and also
# becomes deobfuscate_js_files' input, since beautified source is easier to
# pattern-match structurally. Requires the js-beautify binary (pip package:
# jsbeautifier); skips quietly if it's not installed, leaving every
# <name>.js as-is for deobfuscate_js_files to handle directly. If js-beautify
# itself errors on a specific file, that one file is left as <name>.js too
# (never moved) rather than losing it.
#
# Skips any <name>.js whose <name>.beautify.js sibling already exists: that
# means a previous crawler_js pass (this function runs once per call, and
# crawler_js runs multiple times per host across a recon) already moved it
# and deobfuscate_js_files has since (re)created <name>.js from it — without
# this guard, re-running would beautify the ALREADY-DEOBFUSCATED <name>.js
# and overwrite the original audit copy with it, losing the "still
# obfuscated" reference.
#
# Args:
#   $1 - directory to beautify recursively (default: ${webapp_js_dir})
beautify_js_files(){
    local scan_dir="${1:-${webapp_js_dir}}"
    local js_file beautify_file total=0

    [[ ! -d "${scan_dir}" ]] && return 0
    if ! command -v js-beautify > /dev/null 2>&1; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} JS beautify: js-beautify binary not found, skipping."
        return 1
    fi

    while IFS= read -r js_file; do
        [[ -z "${js_file}" ]] && continue
        beautify_file="${js_file%.js}.beautify.js"

        [[ -s "${beautify_file}" ]] && continue

        echo "js-beautify --quiet -o \"${beautify_file}\" \"${js_file}\"" >> "${log_execution_file}"
        if js-beautify --quiet -o "${beautify_file}" "${js_file}" >> "${log_execution_file}" 2>&1 \
            && [[ -s "${beautify_file}" ]]; then
            rm -f "${js_file}"
            total=$((total+1))
        else
            rm -f "${beautify_file}"
        fi
    done < <(find "${scan_dir}" -type f -name '*.js' ! -name '*.beautify.js')

    if [[ "${total}" -gt 0 ]]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} JS beautify: ${total} file(s) formatted and moved to *.beautify.js."
    fi
}

# Detect and reverse common JavaScript obfuscation techniques (hex/unicode
# string escapes, base64-in-atob, Dean Edwards packer, javascript-obfuscator's
# string-array + decoder encoding) by driving js_deobfuscator.py (support/
# runtime/scripts/) against every candidate left by beautify_js_files.
#
# Each candidate is either a <name>.beautify.js (the common case — moved
# there by beautify_js_files) or a bare <name>.js that beautify_js_files
# left untouched (js-beautify missing entirely, or it errored on that one
# file). For a .beautify.js candidate, the result is written to a NEW
# <name>.js (created here, never existed before this point); for a bare
# <name>.js candidate, the result replaces that same path. Either way,
# <name>.beautify.js — when it exists — is never modified by this function;
# it stays as the pretty-but-still-obfuscated reference.
#
# js_deobfuscator.py reports which techniques it actually reversed in
# --relatorio-json's "acoes_aplicadas" list. When that list is empty (file
# wasn't obfuscated, just minified/plain), we discard the tool's own stdout
# and byte-copy the input straight into <name>.js instead of trusting its
# rewritten output: the script reads/writes text as UTF-8 with
# errors="replace" (see processar_arquivo()/Path.read_text), so
# re-serializing a file it didn't actually need to touch risks silently
# mangling any non-UTF-8 byte in it. A plain copy has no such risk.
#
# If python3/jq are missing, or the script itself is missing, the function
# can't run the deobfuscator at all — but it still copies every
# <name>.beautify.js into <name>.js (skipped only for bare <name>.js
# candidates, which are already at their final path). Without this, a host
# missing those dependencies would have every downloaded file sitting only
# as <name>.beautify.js, invisible to scan_js_secrets/scan_js_params below
# (they deliberately exclude *.beautify.js).
#
# Run this AFTER beautify_js_files and BEFORE scan_js_secrets /
# scan_js_params so the secret/sink grep below sees restored literals
# instead of obfuscator-decoder calls. js_deobfuscator.py itself degrades
# gracefully when `node` is absent (only the string-array and Dean Edwards
# passes need it; every other technique is pure-Python regex).
#
# Args:
#   $1 - directory to deobfuscate recursively (default: ${webapp_js_dir})
deobfuscate_js_files(){
    local scan_dir="${1:-${webapp_js_dir}}"
    local script="${collector_js_deobfuscator}"
    local input_file final_js tmp_out tmp_report actions
    local total=0 copied=0 failed=0
    local runnable=1

    [[ ! -d "${scan_dir}" ]] && return 0

    if ! command -v python3 > /dev/null 2>&1; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} JS deobfuscate: python3 not found — promoting *.beautify.js copies as-is."
        runnable=0
    elif ! command -v jq > /dev/null 2>&1; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} JS deobfuscate: jq not found — promoting *.beautify.js copies as-is."
        runnable=0
    elif [[ ! -s "${script}" ]]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} JS deobfuscate: script missing → ${script} — promoting *.beautify.js copies as-is."
        runnable=0
    fi

    while IFS= read -r input_file; do
        [[ -z "${input_file}" ]] && continue
        if [[ "${input_file}" == *.beautify.js ]]; then
            final_js="${input_file%.beautify.js}.js"
            # <name>.js already produced by an earlier crawler_js pass over
            # this same webapp_js_dir (crawler_js runs multiple times per
            # host across a recon) — don't reprocess, don't reclobber.
            [[ -s "${final_js}" ]] && continue
        else
            final_js="${input_file}"
            # A bare <name>.js that already has a <name>.beautify.js
            # sibling can only be the finalized output of an earlier
            # deobfuscate_js_files pass — a fresh raw download never
            # coexists with its own .beautify.js (beautify_js_files moves
            # it away). Skip reprocessing it through the deobfuscator again.
            [[ -s "${input_file%.js}.beautify.js" ]] && continue
        fi

        if [[ "${runnable}" -eq 0 ]]; then
            [[ "${final_js}" != "${input_file}" ]] && cp -f "${input_file}" "${final_js}"
            continue
        fi

        tmp_out="${final_js}.deof.tmp"
        tmp_report="${final_js}.deof.report.tmp"

        echo "timeout ${js_deobfuscate_timeout} python3 \"${script}\" \"${input_file}\" -o \"${tmp_out}\" --relatorio-json \"${tmp_report}\"" >> "${log_execution_file}"
        if timeout "${js_deobfuscate_timeout}" python3 "${script}" "${input_file}" -o "${tmp_out}" --relatorio-json "${tmp_report}" >> "${log_execution_file}" 2>&1 \
            && [[ -s "${tmp_out}" ]] && [[ -s "${tmp_report}" ]]; then
            actions="$(jq '.acoes_aplicadas | length' "${tmp_report}" 2>/dev/null)"
            if [[ "${actions}" =~ ^[0-9]+$ ]] && [[ "${actions}" -gt 0 ]]; then
                mv -f "${tmp_out}" "${final_js}"
                total=$((total+1))
            else
                # No technique actually applied — keep the original bytes
                # as-is instead of the tool's UTF-8-round-tripped stdout.
                # Skip the copy when final_js IS input_file already (bare
                # <name>.js candidate, nothing to copy from) — cp refuses a
                # no-op self-copy as an error.
                rm -f "${tmp_out}"
                [[ "${final_js}" != "${input_file}" ]] && cp -f "${input_file}" "${final_js}"
                copied=$((copied+1))
            fi
        else
            rm -f "${tmp_out}"
            [[ "${final_js}" != "${input_file}" ]] && cp -f "${input_file}" "${final_js}"
            failed=$((failed+1))
        fi
        rm -f "${tmp_report}"
    done < <(find "${scan_dir}" -type f -name '*.js')

    if [[ "${total}" -gt 0 ]]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} JS deobfuscate: ${total} file(s) deobfuscated."
    fi
    if [[ "${copied}" -gt 0 ]]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} JS deobfuscate: ${copied} file(s) had no obfuscation to reverse, copied as-is."
    fi
    if [[ "${failed}" -gt 0 ]]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} JS deobfuscate: ${failed} file(s) failed or timed out."
    fi
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
    local patterns_file="${collector_secrets_patterns}"
    local label regex hits line total
    local channel="${notify_high_channel:-${notify_recon_channel}}"

    [[ ! -d "${scan_dir}" ]] && return 0
    if [[ ! -s "${patterns_file}" ]]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} JS secrets: pattern file missing → ${patterns_file}"
        return 1
    fi

    : > "${out_file}"
    {
        echo "# JS secret-scan report for ${domain}"
        echo "# scan_dir: ${scan_dir}"
        echo "# patterns: ${patterns_file}"
        echo "# date: $(date +"%Y-%m-%d %H:%M:%S")"
        echo "# format: <label>:<file>:<line>:<match>"
        echo
    } >> "${out_file}"

    total=0
    while IFS='|' read -r label regex; do
        # Skip blanks and comments. Require both fields.
        [[ -z "${label}" || "${label}" =~ ^[[:space:]]*# || -z "${regex}" ]] && continue
        # --exclude *.beautify.js: that copy is deobfuscate_js_files' input,
        # not its output — scanning it too would double-count every hit
        # that survived (or never needed) deobfuscation.
        hits="$(grep -rEHnIoi --include='*.js' --exclude='*.beautify.js' "${regex}" "${scan_dir}" 2>/dev/null)"
        [[ -z "${hits}" ]] && continue
        while IFS= read -r line; do
            printf '%s:%s\n' "${label}" "${line}" >> "${out_file}"
            total=$((total+1))
        done <<< "${hits}"
    done < "${patterns_file}"

    if [[ "${total}" -gt 0 ]]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} JS secrets: ${total} candidate(s) flagged → ${out_file}"
        {
            echo "JS secret candidates for ${domain}: ${total}"
            echo "Report: ${out_file}"
            echo
            grep -v '^#' "${out_file}" | grep -v '^$' | head -n 30
            [[ "${total}" -gt 30 ]] && echo "... ($((total - 30)) more)"
        } | notify "${notify_options[@]}" -id "${channel}" > /dev/null 2>&1
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
    local patterns_file="${collector_params_patterns}"
    local label regex hits line total
    local channel="${notify_recon_channel}"

    [[ ! -d "${scan_dir}" ]] && return 0
    if [[ ! -s "${patterns_file}" ]]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} JS sinks: pattern file missing → ${patterns_file}"
        return 1
    fi

    : > "${out_file}"
    {
        echo "# JS param/sink scan report for ${domain}"
        echo "# scan_dir: ${scan_dir}"
        echo "# patterns: ${patterns_file}"
        echo "# date: $(date +"%Y-%m-%d %H:%M:%S")"
        echo "# format: <category>:<file>:<line>:<match>"
        echo "# NOTE: a hit means \"worth a manual look\", not \"vulnerable\"."
        echo
    } >> "${out_file}"

    total=0
    while IFS='|' read -r label regex; do
        [[ -z "${label}" || "${label}" =~ ^[[:space:]]*# || -z "${regex}" ]] && continue
        # --exclude *.beautify.js: see scan_js_secrets for why.
        hits="$(grep -rEHnIoi --include='*.js' --exclude='*.beautify.js' "${regex}" "${scan_dir}" 2>/dev/null)"
        [[ -z "${hits}" ]] && continue
        while IFS= read -r line; do
            printf '%s:%s\n' "${label}" "${line}" >> "${out_file}"
            total=$((total+1))
        done <<< "${hits}"
    done < "${patterns_file}"

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
        } | notify "${notify_options[@]}" -id "${channel}" > /dev/null 2>&1
    fi
}
