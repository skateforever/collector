#!/bin/bash
#############################################################
#                                                           #
# LLM JSON report builder.                                  #
#                                                           #
# Walks every file collector wrote under ${report_dir} this #
# run (recursively — scan/, webapp/tech, webapp/enum,       #
# webapp/params, webapp/javascript, webapp/aquatone, the     #
# history CSV, all of it) and packs it into one JSON         #
# document: ${report_dir}/collector-report-<target>.json.    #
#                                                           #
# Meant to be handed to an LLM ALONGSIDE llm-prompt.txt      #
# (functions/llm_prompt.sh) — that file already carries the  #
# analysis directive/instructions as a text blob; this one   #
# is the same run's raw output in a structured, machine-      #
# parseable form (e.g. for an API call that wants JSON        #
# rather than a pasted text file).                            #
#                                                           #
# Exposes:                                                  #
#   * build_llm_json    (top-level orchestrator)            #
#                                                           #
#############################################################

# Generates ${report_dir}/collector-report-<target>.json from EVERY regular
# file under ${report_dir} (recursive — unlike build_llm_prompt, which only
# concatenates a fixed, curated artifact list, this walks the directory
# tree as it actually exists on disk, so it also picks up webapp/tech,
# webapp/enum, webapp/params, webapp/javascript and webapp/aquatone).
#
# Shape:
#   {
#     "target": "...", "generated_at": "...", "report_dir": "...",
#     "files": {
#        "domains_found.txt": {"path": "...", "size": N, "lines": N, "binary": false, "content": "..."},
#        "webapp/aquatone/some-host.png": {"path": "...", "size": N, "lines": null, "binary": true, "content": null},
#        ...
#     }
#   }
#
# Keys are paths relative to ${report_dir} (forward slashes, nested dirs
# included as-is). A text file's full content is embedded verbatim
# (same no-truncation philosophy as build_llm_prompt); a binary file
# (aquatone's PNGs, mainly) gets its metadata only — "content": null,
# "binary": true — embedding image bytes as escaped JSON would bloat the
# document for no benefit to a text-based LLM call.
#
# llm-prompt.txt itself is skipped: it's sent as its own file alongside
# this one, so embedding it here would just duplicate the same bytes
# twice in the same LLM call. Any collector-report-*.json from a PRIOR
# run is skipped too — only relevant in "reuse" mode (webapp_enum_check
# reusing an existing recon_dir — see create_directory_structure), where
# this function's own prior output could otherwise sit in ${report_dir}
# and get recursively embedded inside this run's output.
#
# Requires jq (already a hard dependency — see check_binaries.sh) and
# grep -I for the text/binary split. Skips quietly (return 1) if jq is
# missing, same failure style as the other report builders in this file
# family.
build_llm_json(){
    local target="${domain:-${url_domain:-unknown}}"
    local ts="$(date +"%Y-%m-%dT%H:%M:%S%z")"
    local out="${report_dir}/collector-report-${target}.json"
    local items_file f rel size lines total=0

    [[ ! -d "${report_dir}" ]] && return 0
    if ! command -v jq > /dev/null 2>&1; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} build_llm_json: jq binary not found, skipping."
        return 1
    fi

    # Stage one jq object per file into a newline-delimited file, then fold
    # them all into the final document in one jq invocation — doing it
    # incrementally (one jq call writing straight into ${out}) risks a
    # partially-written document if a later file's jq call fails midway.
    items_file="$(mktemp "${tmp_dir}/llm_json_items.XXXXXX")" || return 1
    : > "${items_file}"

    while IFS= read -r -d '' f; do
        rel="${f#${report_dir}/}"
        case "${rel}" in
            llm-prompt.txt|collector-report-*.json) continue ;;
        esac

        size="$(wc -c < "${f}" 2>/dev/null | tr -d ' ')"
        if [[ ! -s "${f}" ]]; then
            jq -n --arg rel "${rel}" --arg path "${f}" \
                '{($rel): {path: $path, size: 0, lines: 0, binary: false, content: ""}}' \
                >> "${items_file}" 2>> "${log_execution_file}"
        elif grep -Iq '' "${f}" 2>/dev/null; then
            lines="$(wc -l < "${f}" 2>/dev/null | tr -d ' ')"
            jq -n --arg rel "${rel}" --arg path "${f}" --argjson size "${size}" --argjson lines "${lines}" \
                --rawfile content "${f}" \
                '{($rel): {path: $path, size: $size, lines: $lines, binary: false, content: $content}}' \
                >> "${items_file}" 2>> "${log_execution_file}"
        else
            jq -n --arg rel "${rel}" --arg path "${f}" --argjson size "${size}" \
                '{($rel): {path: $path, size: $size, lines: null, binary: true, content: null}}' \
                >> "${items_file}" 2>> "${log_execution_file}"
        fi
        total=$((total+1))
    done < <(find "${report_dir}" -type f -print0 | sort -z)

    if [[ "${total}" -eq 0 ]]; then
        rm -f "${items_file}"
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} build_llm_json: no files found under ${report_dir}, skipping."
        return 0
    fi

    jq -n --arg target "${target}" --arg ts "${ts}" --arg report_dir "${report_dir}" \
        --slurpfile items "${items_file}" \
        '{
            target: $target,
            generated_at: $ts,
            report_dir: $report_dir,
            files: (reduce $items[] as $item ({}; . + $item))
        }' > "${out}" 2>> "${log_execution_file}"

    rm -f "${items_file}"

    if [[ -s "${out}" ]]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} LLM JSON report written → ${out} (${total} file(s))"
    else
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} build_llm_json: failed to write ${out} (see ${log_execution_file})."
        return 1
    fi
}
