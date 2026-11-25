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
        # Printed HERE, immediately — no longer deferred to cleanup_global.
        # It used to be deferred so it would land as the LAST line, after
        # cleanup_global's own shutdown steps — but with -ru|--report-up,
        # start_web_report (called right after this in domains_recon.sh/
        # url_recon.sh) can be followed by _collector_hold_for_dashboard
        # blocking for as long as the dashboard stays up (minutes to
        # hours). Deferring meant "finished!" only appeared once the
        # container was stopped, instead of right after the run actually
        # finished. Printing immediately fixes that; a plain run (no
        # --report-up) is unaffected since cleanup_global never had
        # anything of substance to print after this line anyway.
        _collector_final_message="${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} The reconnaissance on ${yellow}${target}${reset} ${green}finished!${reset}"
        echo -e "${_collector_final_message}"
        [[ -n "${log_execution_file:-}" ]] && echo -e "${_collector_final_message}" >> "${log_execution_file}"
        # message() usually runs inside domains_recon()/url_recon()'s own
        # subshell (their body is wrapped in one so cleanup_on_exit/tee
        # scope correctly) — a subshell is a forked child, so the variable
        # assignment above never reaches collector's own process. The file
        # below is now only a safety net for cleanup_global running
        # WITHOUT message() ever having been called (e.g. a crash earlier
        # in the pipeline) — the normal path no longer depends on it to
        # get this line printed at the right time, since it's already
        # printed above.
        [[ -n "${output_dir:-}" ]] && printf '%s' "${_collector_final_message}" > "${output_dir}/.final_message.$$" 2>/dev/null
        echo "The reconnaissance on ${target} finished at $(date +"%Y%m%d %H:%M")!" | notify "${notify_options[@]}" -id "${notify_recon_channel}" > /dev/null 2>&1
    fi
    if [ "${status}" == "failed" ]; then
        # See the "finished" branch above — same reasoning, printed
        # immediately now instead of deferred to cleanup_global.
        _collector_final_message="${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} The reconnaissance on ${yellow}${target}${reset} ${red}failed!${reset}"
        echo -e "${_collector_final_message}"
        [[ -n "${log_execution_file:-}" ]] && echo -e "${_collector_final_message}" >> "${log_execution_file}"
        [[ -n "${output_dir:-}" ]] && printf '%s' "${_collector_final_message}" > "${output_dir}/.final_message.$$" 2>/dev/null
        echo "The reconnaissance on ${target} failed at $(date +"%Y%m%d %H:%M")!" | notify "${notify_options[@]}" -id "${notify_recon_channel}" > /dev/null 2>&1
    fi
}
