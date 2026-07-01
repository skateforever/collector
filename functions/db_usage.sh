#!/bin/bash
#############################################################
#                                                           #
# SQLite ingestion of per-run history rows.                 #
#                                                           #
# The recon flow appends a row to ${target}_history.csv at  #
# the end of each run; db_usage takes that row and mirrors  #
# it into ${output_dir}/collector-results-db so the         #
# app-report dashboard has a single, queryable source of    #
# truth across targets.                                     #
#                                                           #
# Exposes:                                                  #
#   * db_usage                                              #
#                                                           #
#############################################################

# Ingest the current run's row from ${domain}_history.csv into a local
# SQLite database. The DB lives at ${output_dir}/collector-results-db so
# every target on this host writes to a single canonical store; ingestion
# is idempotent on (domain, run_id) — re-running collector for the same
# run_id replaces the row if any column changed, otherwise it's a no-op.
#
# Designed for low-resource VPSes: SQLite means no daemon, WAL keeps
# readers free while the per-run writer runs, and the schema lives in
# support/runtime/schema/collector-results.sql so the rule set is editable
# without touching bash.
#
# Called by the orchestrators right after build_llm_prompt.
db_usage(){
    local target="${domain:-${url_domain}}"
    local hist="${output_dir}/${target}/${target}_history.csv"
    local db="${collector_db:-${output_dir}/${collector_db_name:-collector-results-db}}"
    local schema="${collector_db_schema}"
    local fresh=0

    if ! command -v sqlite3 >/dev/null 2>&1; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} db_usage: sqlite3 binary not found, skipping ingestion."
        return 0
    fi

    if [[ -z "${target}" ]]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} db_usage: no target in scope, skipping."
        return 0
    fi

    if [[ ! -s "${hist}" ]]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} db_usage: history CSV missing → ${hist}"
        return 0
    fi

    if [[ ! -s "${schema}" ]]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} db_usage: schema file missing → ${schema}"
        return 1
    fi

    # Bootstrap the DB the first time we see this host.
    if [[ ! -s "${db}" ]]; then
        fresh=1
        if ! sqlite3 "${db}" < "${schema}" 2>> "${log_execution_file}"; then
            echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} db_usage: failed to create ${db} from schema."
            return 1
        fi
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} db_usage: created ${db} (schema: ${schema})"
    else
        # Apply schema as IF-NOT-EXISTS — covers upgrades that add columns,
        # indexes or views without touching existing data.
        sqlite3 "${db}" < "${schema}" 2>> "${log_execution_file}"
    fi

    # Pull this run's row out of the CSV. The latest row in the file is
    # always the run we just finished — record_history appends.
    local run_id
    run_id="$(basename "${recon_dir}")"

    # Use awk to extract the row matching this run_id (no trailing
    # newline issues, no header row). awk also handles the case where
    # the CSV header order changes — we feed columns positionally, so
    # the schema/CSV column order must match. Guard against that with a
    # header-shape check.
    local header expected
    header="$(head -n 1 "${hist}")"
    expected="domain,run_id,run_date,started_at,finished_at,mode,subdomains,subdomains_alive,subdomains_added,ips,ips_added,webapp_consolidated,webapp_consolidated_added,vhosts_strong,vhosts_added,emails,emails_added,js_secrets,js_params,findings_info,findings_low,findings_medium,findings_high,findings_critical,report_dir,llm_prompt_path,status"
    if [[ "${header}" != "${expected}" ]]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} db_usage: history CSV header drift, refusing to ingest."
        echo "  expected: ${expected}" >> "${log_execution_file}"
        echo "  got:      ${header}"   >> "${log_execution_file}"
        return 1
    fi

    local row
    row="$(awk -F',' -v r="${run_id}" 'NR>1 && $2==r {line=$0} END{print line}' "${hist}")"
    if [[ -z "${row}" ]]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} db_usage: no row for ${run_id} in ${hist}."
        return 1
    fi

    # Hand the single row to sqlite via a temp CSV stage table. Using
    # INSERT OR REPLACE on (domain, run_id) is the idempotency guarantee:
    # a re-run of the same run_id only writes when the row content
    # actually differs; SQLite's REPLACE rewrites the row in place. The
    # outer WHERE EXISTS makes the no-op cheap when nothing changed.
    local stage
    stage="$(mktemp -t collector-stage.XXXXXX.csv)" || return 1
    {
        echo "${expected}"
        echo "${row}"
    } > "${stage}"

    sqlite3 "${db}" 2>> "${log_execution_file}" <<SQL
.bail on
BEGIN IMMEDIATE;
INSERT OR IGNORE INTO targets(domain) VALUES ('${target}');

-- Stage table mirrors the CSV payload columns ONLY (28 cols). Cloning
-- recon_runs verbatim used to pull in \`ingested_at\` too, leaving the
-- column NULL after .import — the subsequent \`SELECT s.*, datetime('now')\`
-- then produced one too many values for the destination table. Define
-- the schema explicitly so the import shape always matches the CSV.
CREATE TEMP TABLE recon_runs_stage (
    domain              TEXT,
    run_id              TEXT,
    run_date            TEXT,
    started_at          TEXT,
    finished_at         TEXT,
    mode                TEXT,
    subdomains          INTEGER,
    subdomains_alive    INTEGER,
    subdomains_added    INTEGER,
    ips                 INTEGER,
    ips_added           INTEGER,
    webapp_consolidated       INTEGER,
    webapp_consolidated_added INTEGER,
    vhosts_strong       INTEGER,
    vhosts_added        INTEGER,
    emails              INTEGER,
    emails_added        INTEGER,
    js_secrets          INTEGER,
    js_params           INTEGER,
    findings_info       INTEGER,
    findings_low        INTEGER,
    findings_medium     INTEGER,
    findings_high       INTEGER,
    findings_critical   INTEGER,
    report_dir          TEXT,
    llm_prompt_path     TEXT,
    status              TEXT
);
.mode csv
.import --skip 1 '${stage}' recon_runs_stage

-- Only write if the incoming row differs from what's already stored.
-- Compare every payload column; ignore ingested_at (server-side default).
-- Columns are listed explicitly on the destination side so a future
-- schema change to recon_runs can't silently misalign the SELECT.
INSERT OR REPLACE INTO recon_runs (
    domain, run_id, run_date, started_at, finished_at, mode,
    subdomains, subdomains_alive, subdomains_added,
    ips, ips_added,
    webapp_consolidated, webapp_consolidated_added,
    vhosts_strong, vhosts_added,
    emails, emails_added,
    js_secrets, js_params,
    findings_info, findings_low, findings_medium, findings_high, findings_critical,
    report_dir, llm_prompt_path, status,
    ingested_at
)
SELECT s.*, datetime('now') AS ingested_at
FROM recon_runs_stage s
LEFT JOIN recon_runs r
       ON r.domain = s.domain AND r.run_id = s.run_id
WHERE r.run_id IS NULL
   OR r.run_date          IS NOT s.run_date
   OR r.started_at        IS NOT s.started_at
   OR r.finished_at       IS NOT s.finished_at
   OR r.mode              IS NOT s.mode
   OR r.subdomains        IS NOT s.subdomains
   OR r.subdomains_alive  IS NOT s.subdomains_alive
   OR r.subdomains_added  IS NOT s.subdomains_added
   OR r.ips               IS NOT s.ips
   OR r.ips_added         IS NOT s.ips_added
   OR r.webapp_consolidated       IS NOT s.webapp_consolidated
   OR r.webapp_consolidated_added IS NOT s.webapp_consolidated_added
   OR r.vhosts_strong     IS NOT s.vhosts_strong
   OR r.vhosts_added      IS NOT s.vhosts_added
   OR r.emails            IS NOT s.emails
   OR r.emails_added      IS NOT s.emails_added
   OR r.js_secrets        IS NOT s.js_secrets
   OR r.js_params         IS NOT s.js_params
   OR r.findings_info     IS NOT s.findings_info
   OR r.findings_low      IS NOT s.findings_low
   OR r.findings_medium   IS NOT s.findings_medium
   OR r.findings_high     IS NOT s.findings_high
   OR r.findings_critical IS NOT s.findings_critical
   OR r.report_dir        IS NOT s.report_dir
   OR r.llm_prompt_path   IS NOT s.llm_prompt_path
   OR r.status            IS NOT s.status;

DROP TABLE recon_runs_stage;
COMMIT;
SQL
    local rc=$?
    rm -f "${stage}"

    if [[ "${rc}" -ne 0 ]]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} db_usage: ingestion failed (see ${log_execution_file})."
        return 1
    fi

    if [[ "${fresh}" -eq 1 ]]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} db_usage: ${target} ${run_id} ingested into fresh DB → ${db}"
    else
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} db_usage: ${target} ${run_id} synced → ${db}"
    fi
}
