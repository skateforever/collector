#!/bin/bash
##################################################################
# This function will display start, finished and failed messages #
#                                                                #
# This file is an essential part of collector's execution!       #
# And is responsible to get the functions:                       #
#                                                                #
#   * message                                                    #
#                                                                #
##################################################################

message(){
    local target="$1"
    local status="$2"
    if [ "${status}" == "start" ]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} The reconnaissance on ${yellow}${target}${reset} ${green}started!${reset}"
        echo "The reconnaissance on ${target} started at $(date +"%Y%m%d %H:%M")!" | notify "${notify_options[@]}" -id "${notify_recon_channel}" > /dev/null 2>&1
    fi
    if [ "${status}" == "finished" ]; then
        # Deferred, not echoed here: cleanup_global (EXIT trap) prints this
        # as the LAST line, after every shutdown/cleanup step, so the run's
        # verdict always reads as the final word instead of appearing
        # before "Graceful shutdown initiated" etc. notify still fires
        # immediately regardless.
        _collector_final_message="${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} The reconnaissance on ${yellow}${target}${reset} ${green}finished!${reset}"
        # message() usually runs inside domains_recon()/url_recon()'s own
        # subshell (their body is wrapped in one so cleanup_on_exit/tee
        # scope correctly) — a subshell is a forked child, so the variable
        # assignment above never reaches collector's own process. $$ stays
        # the same across that boundary though, so cleanup_global can still
        # recover this by reading it back from a $$-scoped file.
        [[ -n "${output_dir:-}" ]] && printf '%s' "${_collector_final_message}" > "${output_dir}/.final_message.$$" 2>/dev/null
        echo "The reconnaissance on ${target} finished at $(date +"%Y%m%d %H:%M")!" | notify "${notify_options[@]}" -id "${notify_recon_channel}" > /dev/null 2>&1
    fi
    if [ "${status}" == "failed" ]; then
        # See the "finished" branch above — same deferral and file-fallback, same reason.
        _collector_final_message="${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} The reconnaissance on ${yellow}${target}${reset} ${red}failed!${reset}"
        [[ -n "${output_dir:-}" ]] && printf '%s' "${_collector_final_message}" > "${output_dir}/.final_message.$$" 2>/dev/null
        echo "The reconnaissance on ${target} failed at $(date +"%Y%m%d %H:%M")!" | notify "${notify_options[@]}" -id "${notify_recon_channel}" > /dev/null 2>&1
    fi
}
