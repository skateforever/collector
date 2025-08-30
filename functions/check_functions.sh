check_functions(){
    # Checking if the essencial functions there are
    for file in diff_recon domains_sources emails_recon infra_recon vhost_check web_data web_detect_page web_git_rebuild; do
        function="${collector_path}/functions/${file}.sh"
        if [ -s "${function}" ]; then
            source "${function}"
        else
            echo -e "Please ${red}make sure${reset} you have the ${yellow}\"${function}\"${reset} file."
            echo -e "${yellow}You need this file to execute collector${reset}!"
            exit 1
        fi
    done
}
