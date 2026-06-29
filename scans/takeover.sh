#!/bin/bash
#############################################################
# Subdomain takeover validation                             #
#                                                           #
# This file is an essential part of collector's execution!  #
# And is responsible to get the functions:                  #
#                                                           #
#   * takeover_scan                                         #
#                                                           #
# Input : ${report_dir}/domains_without_resolution.txt      #
# Output: ${report_dir}/domains_takeover.txt                #
#         Format (TAB-separated):                           #
#           vhost  cname_chain  provider  confidence  fpr   #
#                                                           #
# Confidence:                                               #
#   STRONG  -> CNAME aponta para provedor conhecido AND     #
#              (nuclei matched OR active resource check     #
#              confirma NoSuchBucket/NXDOMAIN apex)         #
#   MEDIUM  -> CNAME -> provedor conhecido, sem confirmação #
#              ativa (revisar manualmente)                  #
#   WEAK    -> só nuclei/subzy/subjack reportou (sem CNAME  #
#              casando) ou apex NXDOMAIN sem fingerprint    #
#                                                           #
# Sources:                                                  #
#   - https://github.com/EdOverflow/can-i-take-over-xyz     #
#   - nuclei-templates/http/takeovers/                      #
#############################################################

# Provedores conhecidos. O array `takeover_fingerprints` é populado em
# tempo de execução a partir do arquivo externo configurado em
# collector.cfg via ${collector_takeover_fingerprints} (default:
# support/runtime/wordlists/takeover-fingerprints.txt).
#
# Cada linha do arquivo segue o formato:
#   "<regex de host de destino do CNAME>|<provider tag>|<fingerprint string esperado no body>"
#
# Linhas começando com '#' e linhas em branco são ignoradas no load.
takeover_fingerprints=()

# Carrega o arquivo de fingerprints para o array global takeover_fingerprints.
# Idempotente: pode ser chamada várias vezes; sempre reescreve o array.
# Retorna 0 com pelo menos uma entrada carregada, 1 se o arquivo está
# ausente/vazio (chamador deve abortar).
takeover_load_fingerprints(){
    local fpr_file="${1:-${collector_takeover_fingerprints}}"
    takeover_fingerprints=()
    if [[ -z "${fpr_file}" || ! -s "${fpr_file}" ]]; then
        return 1
    fi
    local line
    while IFS= read -r line; do
        # ignora comentários e linhas em branco
        [[ -z "${line}" || "${line}" =~ ^[[:space:]]*# ]] && continue
        # remove espaços em branco nas pontas
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "${line}" ]] && continue
        takeover_fingerprints+=("${line}")
    done < "${fpr_file}"
    [[ "${#takeover_fingerprints[@]}" -gt 0 ]]
}

# Cadeia CNAME completa: dig recursivo até A/AAAA ou NXDOMAIN.
# Retorna lista de hosts (CNAMEs encontrados) separados por " -> ".
takeover_cname_chain(){
    local host="$1"
    local depth=0
    local max_depth=8
    local chain="${host}"
    local target
    while [[ "${depth}" -lt "${max_depth}" ]]; do
        target="$(dig +short CNAME "${host}" 2>/dev/null | head -1 | sed 's/\.$//')"
        [[ -z "${target}" ]] && break
        chain="${chain} -> ${target}"
        host="${target}"
        ((depth += 1))
    done
    echo "${chain}"
}

# Verifica se o apex do CNAME está com zona órfã (NXDOMAIN nos NS).
# Sinal muito forte de takeover (especialmente em delegações DNS antigas).
takeover_apex_nxdomain(){
    local fqdn="$1"
    # extrai apex (últimos 2 ou 3 labels — heurística simples)
    local apex
    apex="$(echo "${fqdn}" | awk -F. '{n=NF; if (n<=2) print $0; else print $(n-1)"."$n}')"
    local soa
    soa="$(dig +short SOA "${apex}" 2>/dev/null)"
    if [[ -z "${soa}" ]]; then
        # confirma com status
        local rc
        rc="$(dig +noall +comments "${apex}" 2>/dev/null | grep -oE 'status: [A-Z]+' | awk '{print $2}' | head -1)"
        [[ "${rc}" == "NXDOMAIN" || "${rc}" == "SERVFAIL" ]] && return 0
    fi
    return 1
}

# Match do destino do CNAME contra a tabela de fingerprints.
# Imprime "<provider>|<fingerprint>" em stdout, ou nada se não bater.
takeover_match_provider(){
    local cname_target="$1"
    local entry pattern provider fpr
    for entry in "${takeover_fingerprints[@]}"; do
        pattern="${entry%%|*}"
        provider="$(echo "${entry}" | awk -F'|' '{print $2}')"
        fpr="$(echo "${entry}" | awk -F'|' '{print $3}')"
        if echo "${cname_target}" | grep -Eiq "${pattern}"; then
            echo "${provider}|${fpr}"
            return 0
        fi
    done
    return 1
}

# Confirmação ativa: faz um GET no vhost e procura a fingerprint no body.
takeover_confirm_http(){
    local vhost="$1"
    local fpr="$2"
    [[ -z "${fpr}" ]] && return 1
    local user_agent body proto
    user_agent="$(get_user_agent 2>/dev/null || echo 'Mozilla/5.0')"
    for proto in https http; do
        body="$(curl "${curl_options_fast[@]}" -H "User-Agent: ${user_agent}" "${proto}://${vhost}/" 2>> "${log_execution_file}")"
        if echo "${body}" | grep -Fq "${fpr}"; then
            return 0
        fi
    done
    return 1
}

# Confirmação ativa específica de S3 (bucket existe ou não).
takeover_confirm_s3(){
    local cname_target="$1"
    local bucket
    # s3 estilos: <bucket>.s3.amazonaws.com, <bucket>.s3-website-...
    bucket="$(echo "${cname_target}" | sed -E 's/\.s3([.-][^.]+)?\.amazonaws\.com\.?$//')"
    [[ -z "${bucket}" || "${bucket}" == "${cname_target}" ]] && return 1
    # HEAD direto no endpoint
    local code
    code="$(curl "${curl_options_fast[@]}" -o /dev/null -w '%{http_code}' "https://${bucket}.s3.amazonaws.com/" 2>> "${log_execution_file}")"
    [[ "${code}" == "404" ]] && return 0
    return 1
}

takeover_scan(){
    local target="${1:-${domain}}"
    local input_file="${2:-${report_dir}/domains_without_resolution.txt}"
    local output_file="${report_dir}/domains_takeover.txt"
    local nuclei_out="${nuclei_dir:-${report_dir}}/nuclei_takeover.txt"
    local subzy_out="${tmp_dir}/subzy_takeover.tmp"
    local subjack_out="${tmp_dir}/subjack_takeover.tmp"
    local fqdn chain final_cname match provider fpr confidence apex_dead
    local critical_findings=0 high_findings=0

    echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Initializing subdomain takeover validation..."

    if [[ ! -s "${input_file}" ]]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} ${input_file} not found or empty — nothing to validate."
        return 0
    fi

    # Carrega a tabela de fingerprints do arquivo externo. Sem ela o
    # matcher de CNAME fica inútil — interrompe cedo com mensagem clara.
    if ! takeover_load_fingerprints "${collector_takeover_fingerprints}"; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Takeover fingerprints file missing or empty (${collector_takeover_fingerprints:-unset})."
        echo "Takeover fingerprints file missing or empty (${collector_takeover_fingerprints:-unset})." \
            | notify "${notify_options[@]}" -id "${notify_recon_channel}" > /dev/null 2>&1
        return 1
    fi
    echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Loaded ${#takeover_fingerprints[@]} provider fingerprints."

    : > "${output_file}"

    # 1) nuclei takeover templates (silent, mantém o padrão de nuclei.sh)
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Running nuclei takeover templates... "
    if command -v nuclei > /dev/null 2>&1; then
        nuclei -no-color -silent -update-templates > /dev/null 2>&1
        echo "nuclei -l ${input_file} -t http/takeovers/ -severity high,critical -silent -no-color -o ${nuclei_out}" >> "${log_execution_file}"
        nuclei -l "${input_file}" -t http/takeovers/ -severity high,critical \
            -silent -no-color -o "${nuclei_out}" >> "${log_execution_file}" 2>&1 || true
        echo "Done!"
    else
        echo "Skip (nuclei not installed)"
    fi

    # 2) subzy
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Running subzy... "
    if command -v subzy > /dev/null 2>&1; then
        echo "subzy run --targets ${input_file} --hide_fails --output ${subzy_out}" >> "${log_execution_file}"
        subzy run --targets "${input_file}" --hide_fails --output "${subzy_out}" \
            >> "${log_execution_file}" 2>&1 || true
        echo "Done!"
    else
        echo "Skip (subzy not installed)"
    fi

    # 3) subjack
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Running subjack... "
    if command -v subjack > /dev/null 2>&1; then
        # Use the upstream fingerprints.json bundled by the Dockerfiles at
        # /opt/collector/fingerprints.json. Fall back to subjack defaults
        # if the file isn't present (running outside the container).
        local subjack_fpr_arg=()
        [[ -s "/opt/collector/fingerprints.json" ]] && subjack_fpr_arg=(-c /opt/collector/fingerprints.json)
        echo "subjack -w ${input_file} -t 30 -timeout 30 -ssl ${subjack_fpr_arg[*]} -o ${subjack_out} -v" >> "${log_execution_file}"
        subjack -w "${input_file}" -t 30 -timeout 30 -ssl "${subjack_fpr_arg[@]}" \
            -o "${subjack_out}" -v >> "${log_execution_file}" 2>&1 || true
        echo "Done!"
    else
        echo "Skip (subjack not installed)"
    fi

    # 4) CNAME chain + provider matching + active confirm (loop principal)
    echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Resolving CNAME chains and matching providers... "
    while IFS= read -r fqdn; do
        [[ -z "${fqdn}" ]] && continue
        chain="$(takeover_cname_chain "${fqdn}")"
        final_cname="${chain##* -> }"
        # se não há CNAME, chain == fqdn — só vale como takeover se houver
        # apex NXDOMAIN do próprio domínio (caso raro de NS órfão) OU se
        # nuclei/subzy/subjack tiverem reportado
        if [[ "${chain}" == "${fqdn}" ]]; then
            apex_dead=""
            takeover_apex_nxdomain "${fqdn}" && apex_dead="apex_nxdomain"
            # checa se algum scanner mencionou esse host
            if grep -qF "${fqdn}" "${nuclei_out}" 2>/dev/null \
                || grep -qF "${fqdn}" "${subzy_out}" 2>/dev/null \
                || grep -qF "${fqdn}" "${subjack_out}" 2>/dev/null \
                || [[ -n "${apex_dead}" ]]; then
                printf '%s\t%s\t%s\t%s\t%s\n' \
                    "${fqdn}" "${chain}" "unknown" "WEAK" "${apex_dead:-scanner_hit}" >> "${output_file}"
                ((high_findings += 1))
            fi
            continue
        fi

        # tenta casar com provider conhecido
        if match="$(takeover_match_provider "${final_cname}")"; then
            provider="${match%%|*}"
            fpr="${match##*|}"
            confidence="MEDIUM"
            # confirmação ativa
            if [[ "${provider}" == aws-s3* ]] && takeover_confirm_s3 "${final_cname}"; then
                confidence="STRONG"
            elif takeover_confirm_http "${fqdn}" "${fpr}"; then
                confidence="STRONG"
            elif takeover_apex_nxdomain "${final_cname}"; then
                confidence="STRONG"
            fi
            printf '%s\t%s\t%s\t%s\t%s\n' \
                "${fqdn}" "${chain}" "${provider}" "${confidence}" "${fpr:-n/a}" >> "${output_file}"
            [[ "${confidence}" == "STRONG" ]] && ((critical_findings += 1)) || ((high_findings += 1))
        else
            # provider não-listado mas com CNAME — vale registrar como WEAK
            # se algum scanner pegou OU se apex está morto
            apex_dead=""
            takeover_apex_nxdomain "${final_cname}" && apex_dead="apex_nxdomain"
            if grep -qF "${fqdn}" "${nuclei_out}" 2>/dev/null \
                || grep -qF "${fqdn}" "${subzy_out}" 2>/dev/null \
                || grep -qF "${fqdn}" "${subjack_out}" 2>/dev/null \
                || [[ -n "${apex_dead}" ]]; then
                printf '%s\t%s\t%s\t%s\t%s\n' \
                    "${fqdn}" "${chain}" "unmapped" "WEAK" "${apex_dead:-scanner_hit}" >> "${output_file}"
                ((high_findings += 1))
            fi
        fi
    done < "${input_file}"
    echo "Done!"

    sort -u -o "${output_file}" "${output_file}"

    # 5) Notify (mesmo padrão de nuclei.sh)
    if [[ -s "${output_file}" ]]; then
        echo -ne "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Sending takeover notifications... "
        # STRONG -> critical
        grep -P '\tSTRONG\t' "${output_file}" \
            | sed 's/\t/ | /g' \
            | sed "s/^/[takeover-STRONG] ${target} | /" \
            | notify "${notify_options[@]}" -id "${notify_critical_channel}" > /dev/null 2>&1
        # MEDIUM + WEAK -> high (revisar)
        grep -P '\t(MEDIUM|WEAK)\t' "${output_file}" \
            | sed 's/\t/ | /g' \
            | sed "s/^/[takeover-review] ${target} | /" \
            | notify "${notify_options[@]}" -id "${notify_high_channel}" > /dev/null 2>&1
        echo "Done!"
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Takeover scan finished: ${critical_findings} STRONG / ${high_findings} review (see ${output_file})."
    else
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} Takeover scan finished: no findings."
    fi
}

# Se chamado direto (não via source), executa standalone.
# Uso: takeover.sh <domain> <input_file> [report_dir]
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -lt 2 ]]; then
        echo "Usage: $0 <domain> <domains_without_resolution.txt> [report_dir]"
        echo "       Optional env: tmp_dir, nuclei_dir, log_execution_file, notify_options[], notify_*_channel"
        exit 1
    fi
    domain="$1"
    input_file_arg="$2"
    report_dir="${3:-$(dirname "${input_file_arg}")}"
    tmp_dir="${tmp_dir:-/tmp}"
    nuclei_dir="${nuclei_dir:-${report_dir}}"
    log_execution_file="${log_execution_file:-/tmp/takeover_$$.log}"
    # defaults pra rodar sem o collector
    yellow=""; red=""; green=""; reset=""
    [[ ${#curl_options_fast[@]} -eq 0 ]] && curl_options_fast=(-k -s --connect-timeout 5 --max-time 15 --max-redirs 3 --proto-redir =http,https)
    [[ ${#notify_options[@]} -eq 0 ]] && notify_options=(-silent)
    [[ -z "${notify_recon_channel}" ]] && notify_recon_channel="recon"
    [[ -z "${notify_critical_channel}" ]] && notify_critical_channel="critical"
    [[ -z "${notify_high_channel}" ]] && notify_high_channel="high"
    # Resolve o arquivo de fingerprints relativo ao script quando não veio do collector.cfg.
    if [[ -z "${collector_takeover_fingerprints}" ]]; then
        _script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        collector_takeover_fingerprints="${_script_dir}/../support/runtime/wordlists/takeover-fingerprints.txt"
    fi
    type get_user_agent >/dev/null 2>&1 || get_user_agent(){ echo "Mozilla/5.0 (X11; Linux x86_64) takeover-scan/1.0"; }
    takeover_scan "${domain}" "${input_file_arg}"
fi
