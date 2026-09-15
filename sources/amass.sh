#!/bin/bash
#############################################################
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * amass-src                                             #
#                                                           #
#############################################################            

amass-src(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing amass... "
    local amass_out="${tmp_dir}/amass_output.tmp"
    local amass_dir="${tmp_dir}/amass_db"
    : > "${amass_out}"
    mkdir -p "${amass_dir}"

    # amass v5's engine rewrite: `enum` no longer writes a results file
    # directly (its -o/-oA flags are defined but unused in the current
    # release) — it only populates a local graph database under -dir.
    # `subs -names -o` is the separate query step that dumps the names
    # collected in that database to a clean, one-per-line text file.
    echo -e "\namass enum ${amass_options[*]} -d ${domain} -dir ${amass_dir}" >> "${log_execution_file}"
    amass enum "${amass_options[@]}" -d "${domain}" -dir "${amass_dir}" 2>> "${log_execution_file}"
    echo -e "\namass enum ${amass_options[*]} -passive -d ${domain} -dir ${amass_dir}" >> "${log_execution_file}"
    amass enum "${amass_options[@]}" -passive -d "${domain}" -dir "${amass_dir}" 2>> "${log_execution_file}"

    echo "amass subs -d ${domain} -dir ${amass_dir} -names -nocolor -silent -o ${amass_out}" >> "${log_execution_file}"
    amass subs -d "${domain}" -dir "${amass_dir}" -names -nocolor -silent -o "${amass_out}" 2>> "${log_execution_file}"
    echo "Done!"
    sleep 1
}

amass-src
