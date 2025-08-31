message(){
    target="$1"
    status="$2"
    if [ "${status}" == "finished" ]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} The reconnaissance on ${yellow}${target}${reset} ${green}finished!${reset}"
        echo "The reconnaissance on ${target} finished at $(date +"%Y%m%d %H:%M")!" | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
    fi
    if [ "${status}" == "failed" ]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} The reconnaissance on ${yellow}${target}${reset} ${red}failed!${reset}"
        echo "The reconnaissance on ${target} failed at $(date +"%Y%m%d %H:%M")!" | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
    fi
    if [ "${status}" == "start" ]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} ${green}The reconnaissance on${reset} ${yellow}${target}${reset} ${green}started!${reset}"
        echo "The reconnaissance on ${target} started at $(date +"%Y%m%d %H:%M")!" | notify -nc -silent -id "${notify_recon_channel}" > /dev/null
    fi
    unset target
    unset status
}
