#!/bin/bash
#############################################################
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * hackerone-src                                         #
#                                                           #
#############################################################

hackerone-src(){
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Executing hackerone... "
    # Creates the JSON payload using the GraphQL query.
    payload='{"query":"query {team(handle:\"'"${domain}"'\"){structured_scopes{edges{node{asset_identifier}}}}}"}'
    echo "curl ${curl_options[@]} -H \"Content-Type: application/json\" -d \"${payload}\" -X POST https://hackerone.com/graphql -o ${tmp_dir}/hackerone_output.json" >> "${log_execution_file}"
    # Make the POST requ est using curl.
    curl "${curl_options[@]}" -H "Content-Type: application/json" -d "${payload}" -X POST "https://hackerone.com/graphql" -o "${tmp_dir}/hackerone_output.json" 2>> "${log_execution_file}"
    echo "Done!"
}

hackerone-src
