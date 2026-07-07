# Usage manual — collector

## 1. What collector is and its focus as an offensive tool

`collector` is a Bash script that automates the reconnaissance and information-gathering phase during penetration tests and bug bounty engagements. It runs **exclusively inside a Docker container**, which isolates dependencies (Go, Python, Chromium, nmap, etc.) and guarantees each run starts from a clean, reproducible environment.

The offensive focus is to chain into a single pipeline the steps an attacker would normally execute manually at the start of an external-perimeter test:

- passive and active subdomain enumeration across ~30 OSINT sources (crt.sh, securitytrails, shodan, virustotal, alienvault, commoncrawl, dnsdumpster, rapiddns, hackertarget, whoisxmlapi, and others);
- target-infrastructure enrichment (ASN, IPv4/IPv6 blocks, DNS records, zone transfer);
- port scanning with nmap and Shodan;
- live HTTP(S) service discovery with `httpx` and vhost discovery (arbitrary `Host` header) with STRONG/WEAK classification and automatic injection into the container's `/etc/hosts`;
- directory and file brute-force with `gobuster` + `dirsearch`, `robots.txt` and `sitemap.xml` capture, screenshots with `aquatone`;
- JS crawling with `katana` + `waybackurls`, parameter mining, sink classification (SQLi/XSS/SSRF/XXE/CMD) and hardcoded-secret hunting (API keys, JWTs, tokens);
- target email harvesting via Hunter.io, IntelX, Lampyre, Snov.io and a crawl of the consolidated URL list;
- subdomain-takeover detection (`subjack`, `subzy` + custom fingerprints);
- web vulnerability scanning with `nuclei`;
- per-artifact diff between runs (only deltas are pushed to the notification channel);
- packaging of all artifacts into a single `llm-prompt.txt` ready for LLM follow-up analysis;
- idempotent ingestion into SQLite and a read-only Flask + HTMX dashboard for later queries.

In short: `collector` is the automated **attack-surface discovery** stage, designed to hand the operator a solid, organized baseline before the exploitation phase.

## 2. Repository tree

```
collector/
├── Dockerfile                          symlink → Dockerfile-debian (default image)
├── Dockerfile-debian                   official image (python:3.12-slim + Go + Chromium)
├── Dockerfile-archlinux                alternative Arch-based image
├── docker-compose.yml                  ready-to-use service: volumes and -p pre-configured
├── README.md                           full documentation
├── TODO.md                             internal roadmap
│
├── collector                           main Bash script (container entrypoint)
├── collector-docker                    host wrapper: injects -v / -p and calls docker run
├── collector-update                    update script: git pull + conditional rebuild
├── collector.cfg                       config: timeouts, threads, port lists, API keys
│
├── functions/                          Bash modules loaded by collector
│   ├── utils.sh                        banner, reset_vars, redact_secrets
│   ├── check_binaries.sh               verifies required binaries are present in PATH
│   ├── check_execution.sh              flag validation + collector_acquire_lock (per-target flock)
│   ├── check_structure.sh              builds the per-run directory tree (recon_YYYYMMDD/…)
│   ├── menu.sh                         CLI parser and domain validation
│   ├── usage.sh                        help screen
│   ├── message.sh                      start/finished/failed messages and notify integration
│   ├── domains_sources.sh              orchestrates calls to every module under sources/
│   ├── domains_recon.sh                main pipeline for -d/-dl (recon + webapp + scan)
│   ├── url_recon.sh                    alternative pipeline for -u (webapp only)
│   ├── files.sh                        joining/organizing subdomains + build_consolidated_urls (URL merge, /etc/hosts injection)
│   ├── diff.sh                         computes per-artifact deltas vs. previous run
│   ├── infra.sh                        ASN/IPv4/IPv6/netblocks + zone transfer
│   ├── emails_recon.sh                 email harvesting via APIs + crawl
│   ├── webapp_discovery.sh             httpx + port list + webapp_consolidated.txt
│   ├── webapp_enum.sh                  gobuster + dirsearch + aquatone + robots/sitemap
│   ├── webapp_crawler.sh               katana + waybackurls + JS and parameter extraction
│   ├── git.sh                          git-dumper for exposed .git/ repositories
│   ├── app_report.sh                   Flask/gunicorn dashboard lifecycle (background + --report-only foreground)
│   ├── cloudflare_tunnel.sh            cloudflared quick-tunnel for the dashboard (opt-in)
│   ├── db_usage.sh                     idempotent SQLite ingestion of the per-run history CSV
│   └── llm_prompt.sh                   build_llm_prompt + llm_emit_artifact (LLM bundle builder)
│
├── scans/                              scanners invoked by the recon pipelines
│   ├── nmap.sh                         port scan
│   ├── shodan.sh                       Shodan API enrichment
│   ├── nuclei.sh                       web vulnerability scan
│   ├── acunetix.sh                     optional Acunetix integration
│   ├── takeover.sh                     subjack + subzy + custom fingerprints
│   └── js_scans.sh                     scan_js_secrets + scan_js_params (regex-based JS static scan)
│
├── sources/                            ~60 OSINT modules — one file per source/technique
│   ├── alienvault.sh, crt.sh, certspotter.sh, securitytrails.sh, virustotal.sh,
│   ├── shodan.sh, censys.sh, fofa.sh, netlas.sh, leakix.sh, urlscan.sh,
│   ├── amass.sh, subfinder.sh, sublist3r.sh, tlsx.sh, waybackurls.sh, urlfinder.sh,
│   ├── katana.sh, spider.sh, robots-sitemap.sh,
│   ├── bruteforce.sh, ns-brute.sh, nsec-walk.sh, ptr-sweep.sh, asn-sweep.sh,
│   ├── caa-enum.sh, dns-mining.sh, srv-enum.sh, zonetransfer.sh,
│   ├── vhost-check.sh, vhost-probe.sh,
│   └── …  (each file exposes a function, invoked by domains_sources.sh)
│
├── support/
│   ├── runtime/                        assets read at execution time
│   │   ├── wordlists/                  vhost-probe-names.txt, user-agents.txt,
│   │   │                               takeover-fingerprints.txt
│   │   ├── patterns/                   regexes for secrets and sensitive parameter names
│   │   ├── prompts/                    header for llm-prompt.txt
│   │   └── schema/                     SQL schema for collector-results-db
│   └── templates/                      drop-ins for automation
│       ├── cron/collector              daily/weekly cron
│       ├── systemd/collector@          systemd timer template
│       └── notify/provider-config.yml  example projectdiscovery/notify provider config
│
├── app-report/                         read-only dashboard (Flask + HTMX + gunicorn)
│   ├── app.py                          routes, reads collector-results-db
│   ├── requirements.txt
│   └── templates/                      index, target, runs, findings, diff, artifact, raw
│
└── demo/                               promo screenshots
```

## 3. Execution flow

The container entrypoint is the `collector` script. The flow is, in short:

1. **Bootstrap.** `collector` loads `functions/utils.sh` (banner, helpers, global-variable reset) and then `source`s `collector.cfg` to inherit timeouts, threads, short/long port lists and API keys.
2. **Module loading.** Every essential file under `functions/` (`menu.sh`, `usage.sh`, `check_*`, `domains_*`, `url_recon.sh`, `webapp_*`, `emails_recon.sh`, `git.sh`, `diff.sh`, `files.sh`, `infra.sh`, plus the app-report/dashboard modules `cloudflare_tunnel.sh`, `app_report.sh`, `db_usage.sh`, `llm_prompt.sh`) and `scans/` (`acunetix.sh`, `nmap.sh`, `nuclei.sh`, `shodan.sh`, `js_scans.sh`) is sourced in sequence.
3. **Validation.** `check_container` confirms execution is happening inside Docker (the script aborts otherwise); `check_binaries` validates the presence of the required tools in PATH.
4. **CLI parsing.** `menu "$@"` processes the flags (`-d`, `-dl`, `-u`, `-r`, `-wd`, `-we`, `-ws`, `-wc`, `-vv`, `-dr`, etc.). `validate_domain` applies a strict regex to each target. With no arguments, `usage` is shown.
5. **Coherence.** `check_execution` validates invalid flag combinations, `check_parameter_conflicts` rejects mutually exclusive ones, `check_directory_permission` ensures `/opt/collector/outputs` is writable.
6. **Per-target lock.** `collector_acquire_lock "${domain}"` uses `flock` to prevent concurrent runs against the same domain (so the `*_diff.txt` artifacts stay consistent).
7. **Directory tree.** `create_directory_structure` builds `outputs/<domain>/recon_YYYYMMDD/{log,tmp,report/{scan/{nmap,nuclei,shodan},webapp/{aquatone,enum,javascript,params,tech}}}`. In "reuse" mode (running `-we`/`-ws`/`-wc` without `-r`), it picks the most recent recon_dir that has a `domains_alive.txt`.
8. **Dry-run exit.** If `-dr` (or `--dry-run`) is passed, the script prints a pre-flight summary (target, IPv4 regex, timeouts, wordlists, port list, proxy, Shodan) and exits 0 without executing recon.
9. **Mode routing.** `domains_recon` (for `-d`/`-dl`) or `url_recon` (for `-u`) decides which subset of the pipeline to execute based on the flags present. The full happy-path for `-d --recon --webapp-discovery --vhost-validation --webapp-enum --webapp-crawler --webapp-scan` is:
   1. `subdomains_recon` — fans out all `sources/` modules in parallel (OSINT APIs + optional DNS bruteforce + amass/subfinder/tlsx);
   2. `joining_subdomains` — `files.sh` consolidates every raw output under `tmp/` into a single deduplicated `domains_found.txt` filtered to the root domain;
   3. `diff_domains` — produces `domains_diff.txt` (delta vs. previous run);
   4. `organizing_subdomains` — splits into `domains_alive.txt` (DNS-resolving) vs. `domains_without_resolution.txt` (vhost candidates), builds `domains_aliases.txt`, `domains_thirdpart.txt`, `domains_excluded.txt`;
   5. `infra_data` — collects ASN, IP blocks, IPv4/IPv6 (internal vs. external), attempts a zone transfer;
   6. `nmap_scan` + `shodan_scan` — port scan on the external IP set;
   7. `webapp_alive` — `httpx` against `domains_alive.txt` across the port list (short with `-wsd` or long with `-wld`);
   8. `vhost_check` + `vhost_probe` **(only when `-vv|--vhost-validation` is passed)** — discover vhosts served by external IPs whose names do not resolve in DNS, classify STRONG/WEAK, write `etc_hosts_file.txt` and inject it into the container's `/etc/hosts` so every downstream tool resolves them transparently. When `vhost_use_ffuf=yes` in `collector.cfg`, `vhost_probe` delegates to `ffuf` for significantly faster wordlist-based discovery;
   9. `build_consolidated_urls` — produces `webapp_consolidated.txt` (every live HTTP(S) URL, DNS + STRONG vhosts);
   10. `webapp_tech` — captures response headers for fingerprinting (in `report/webapp/tech/`);
   11. `emails_recon` — Hunter.io + IntelX (phonebook target=2) + Lampyre + Snov.io + page/JS crawl of the consolidated list;
   12. `crawler_js` + `crawler_params` — katana + waybackurls extract JS, parameters and recursively expand `sitemap.xml`; classify parameters by sink and search for hardcoded secrets;
   13. `nuclei_scan` — vulnerability scan against the consolidated list;
   14. `webapp_enum` — gobuster + dirsearch against the consolidated list, `robots.txt`, `sitemap.xml`; `aquatone_screenshot` for each batch; `git_rebuild` (git-dumper) if exposed `.git/` directories are found;
   15. `diff_artifacts` — generates `*_diff.txt` for each relevant artifact;
   16. `build_llm_prompt` — concatenates every artifact into `llm-prompt.txt` with an instruction header;
   17. `record_history` — appends a row to `<domain>_history.csv` (trend log);
   18. `db_usage` — idempotent upsert of the run into `collector-results-db` (SQLite, WAL, FKs);
   19. `start_app_report` — starts (or reuses) gunicorn on port 8000; optionally brings up a Cloudflare tunnel if `cloudflare_tunnel="yes"`;
   20. `message "${domain}" finished` — sends a final notification via `notify` (Slack/Discord/Telegram/etc., per `provider-config.yaml`).

For `-u <url>`, the pipeline is reduced to webapp_enum + robots + sitemap + crawler + nuclei + aquatone — no subdomain recon, no infrastructure, no nmap/Shodan.

## 4. Expected artifacts and what each one carries

Every final artifact lives under `outputs/<domain>/recon_YYYYMMDD/`:

`log/recon_YYYYMMDD.log` — full execution log (stderr + stdout from the tools), useful for debugging and auditing.

`tmp/` — raw intermediate outputs from each source (crt.sh JSON, dnsrepo HTML, etc.). Can be `tail`'ed during execution; it is the material `joining_subdomains` consolidates.

### Subdomains and DNS
`report/domains_found.txt` — every subdomain discovered, deduplicated and filtered to the root domain.
`report/domains_diff.txt` — only the delta vs. the previous run (feeds the notification).
`report/domains_alive.txt` — subdomains that resolve in DNS; the basis for `webapp_alive`.
`report/domains_without_resolution.txt` — vhost candidates (do not resolve but show up in sources).
`report/domains_excluded.txt` — items filtered out via `-ed`/`-el`.
`report/domains_aliases.txt` — detected CNAMEs (useful for takeover).
`report/domains_thirdpart.txt` — hosts pointing at third-party infra (CDN, SaaS).
`report/zone_transfer.txt` — AXFR result (empty if the server refuses, which is the expected outcome).

### Infrastructure
`report/domains_infrastructure.txt` — consolidated view of the target's infra.
`report/domains_internal_ipv4.txt` / `domains_external_ipv4.txt` / `domains_external_ipv6.txt` — IPs split by context (with `hostname<TAB>ip` mapping).
`report/infra_as.txt` — target ASNs.
`report/infra_ipv4.txt` / `infra_ipv4_diff.txt` / `infra_ipv6.txt` / `infra_blocks.txt` — unique IPs and netblocks (with diff).

### Web
`report/webapp_consolidated.txt` — **the central artifact**: the list of every live HTTP(S) URL (DNS resolution + validated STRONG vhosts). It is the input for gobuster, dirsearch, nuclei, katana and aquatone.
`report/webapp_consolidated_diff.txt` — between-runs delta (operator's focus).
`report/etc_hosts_file.txt` — `ip<TAB>hostname` map injected into the container's `/etc/hosts` so every tool resolves WEAK/STRONG vhosts transparently.
`report/vhost_subdomains.txt` / `vhost_subdomains_weak.txt` / `vhost_subdomains_diff.txt` — vhost hits classified by confidence, with their delta.
`report/robots_urls.txt` — URLs extracted from the harvested `robots.txt` files.
`report/sitemap_urls.txt` — URLs harvested recursively from `sitemap.xml`/`sitemapindex`.
`report/webapp_js_secrets.txt` — secrets, tokens, JWTs and API keys found in downloaded JS.
`report/webapp_js_params.txt` — discovered parameters + sink classification (SQLi, XSS, SSRF, XXE, CMD, etc.).

### Emails
`report/email_recon.txt` / `email_recon_diff.txt` — target email addresses (APIs + crawl), filtered by the root domain.

### Scans
`report/scan/nmap/nmap_scan.txt` — nmap output against the external IP set.
`report/scan/shodan/shodan_scan.txt` — Shodan API enrichment (ports, banners, CVEs).
`report/scan/nuclei/nuclei_scan.result` — nuclei findings against `webapp_consolidated.txt`.
`report/scan/nuclei/nuclei_scan_diff.txt` — finding delta between runs.
`report/scan/nuclei/nuclei_web_fuzzing.result` — fuzzing-template-specific output.

### Webapp enum
`report/webapp/aquatone/` — HTML+PNG screenshots of every live URL (quick view of the surface).
`report/webapp/enum/` — raw gobuster and dirsearch output per host.
`report/webapp/javascript/` — downloaded JS files (input for `webapp_js_secrets`/`webapp_js_params`).
`report/webapp/params/` — raw katana and waybackurls output.
`report/webapp/tech/` — response headers for fingerprinting (Server, X-Powered-By, etc.).

### Synthesis and persistence
`report/llm-prompt.txt` — single bundle with every artifact above plus an instruction header; ready to paste into any LLM for follow-up analysis.
`<domain>_history.csv` (one level above, at `outputs/<domain>/`) — one row per run, feeds the trend view in the dashboard.
`outputs/collector-results-db` — SQLite with `targets(domain PK)` + `recon_runs(domain, run_id, ...)` + `latest_run` view. Idempotent: re-running the same `run_id` only writes when the payload changes.

## 5. How to run collector

### 5.0. Keeping collector up to date

The `collector-update` script automates pulling changes and rebuilding the Docker image **only when necessary**:

```bash
./collector-update              # git pull + conditional rebuild
./collector-update --pull-only  # git pull without building
./collector-update --build-only # rebuild without pulling
./collector-update --force-build # rebuild even if no structural changes
```

The script inspects changed files and only triggers an image rebuild when **structural files** change (Dockerfiles, `functions/check_binaries.sh`). Script-only changes are served instantly via volume mounts in `collector-docker`, so no rebuild is needed.

Optional: install the `post-merge` git hook to auto-rebuild after every `git pull`:

```bash
git config core.hooksPath support/templates/githooks
# Now git pull automatically triggers rebuild when structural files change
```

**Important note:** `collector-docker` mounts scripts (`collector`, `functions/`, `scans/`, `sources/`, `support/runtime/`) as read-only volumes from the host. This means code changes are instantly available without rebuilding the Docker image. The image only needs rebuilding when binaries or system packages change.

### 5.1. Pre-flight validation (dry run)

Before kicking off a long-running pipeline, use `-dr` (or `--dry-run`) to validate that config, locks, and directory permissions are in order:

```bash
collector-docker -d example.com --recon --webapp-discovery --webapp-short-detection -dr
```

This executes every pre-flight check (CLI parsing, domain validation, directory creation, lock acquisition) and prints a summary of resolved parameters. It exits 0 on success without generating any traffic.

The examples below use the `collector-docker` wrapper, which automatically injects the volumes (`outputs`, `wordlists`, `collector.cfg`) and `-p 127.0.0.1:8000:8000`. The same commands work directly with `docker run --rm -v … collector:latest <flags>` or `docker compose run --rm collector <flags>`.

### 5.2. Basic reconnaissance commands

Pure recon — only discovers subdomains, infra, ASN, IPs and runs nmap/Shodan. No HTTP traffic:

```bash
collector-docker -d example.com --recon
```

What you get: `domains_found.txt`, `domains_alive.txt`, `domains_without_resolution.txt`, `infra_*.txt`, `scan/nmap/nmap_scan.txt`, `scan/shodan/shodan_scan.txt`, `email_recon.txt`. A good first step to map the perimeter without generating noisy HTTP traffic.

Recon + web application discovery using the short port list (defined in `collector.cfg` as `web_port_short_detection`):

```bash
collector-docker -d example.com --recon --webapp-discovery --webapp-short-detection
```

What you get: everything from the previous command plus `webapp_consolidated.txt` (live HTTP(S) URLs) and `webapp/tech/` with fingerprinting headers. This is the typical entry point for any new target. **Note:** vhost discovery (`vhost_subdomains.txt`, `etc_hosts_file.txt`) requires adding `-vv|--vhost-validation`.

Recon + web application discovery **with vhost validation**:

```bash
collector-docker -d example.com --recon --webapp-discovery --webapp-short-detection --vhost-validation
```

What you get: everything above plus `vhost_subdomains.txt` (STRONG), `vhost_subdomains_weak.txt`, `etc_hosts_file.txt`. Vhost validation probes every IP in `infra_ipv4.txt` on the configured port list using dual-tool (curl + httpx) cross-validation, and optionally `ffuf` for the wordlist-based probe.

### 5.3. Intermediate commands

Directory and file enumeration against an existing recon (reuses the most recent `recon_YYYYMMDD/`):

```bash
collector-docker -d example.com --webapp-enum \
  --webapp-wordlists /opt/collector/wordlists/common.txt
```

What you get: `webapp/enum/` (gobuster + dirsearch), `robots_urls.txt`, `sitemap_urls.txt`, `webapp/aquatone/` (screenshots) and, if any `.git/` is exposed, `git-dumper` rebuilds the repository.

> **Wordlist paths are resolved inside the container.** The argument to `--webapp-wordlists` (and to `-s|--subdomain-brute`) is validated by a bash `[[ -s ... ]]` test that runs *inside* the container — so a plain host path like `~/my.txt` fails even though the file exists on the host. Stage the wordlist under `${WORDLISTS_DIR}` (default: `<root>/wordlists`, mounted at `/opt/collector/wordlists`) and pass the container-side path (as in the example above), or override `WORDLISTS_DIR=<dir-that-contains-your-file>` when invoking `collector-docker` so the wrapper mounts that directory instead.

JS crawler and parameter mining (also reuse):

```bash
collector-docker -d example.com --webapp-crawler
```

What you get: `webapp/javascript/` (downloaded JS), `webapp/params/` (katana + waybackurls output), `webapp_js_secrets.txt` (hardcoded keys/tokens/JWTs) and `webapp_js_params.txt` (parameters with sink classification). Focus on finding injection vectors for the exploitation phase.

Standalone vulnerability scan (also reuse):

```bash
collector-docker -d example.com --webapp-scan
```

What you get: `scan/nuclei/nuclei_scan.result` and `nuclei_scan_diff.txt` against `webapp_consolidated.txt`.

Recon against a list of targets (cron/mass scheduling) with scope filtering:

```bash
collector-docker -dl /opt/collector/outputs/targets.list \
  --recon --webapp-discovery --webapp-short-detection \
  -el /opt/collector/outputs/exclude.list
```

What you get: the full pipeline per target, with an independent lock per domain and each target writing into its own `outputs/<domain>/recon_YYYYMMDD/`.

Single URL (no subdomain recon, no nmap/Shodan, no vhost discovery):

```bash
collector-docker -u https://app.example.com \
  --webapp-wordlists /opt/collector/wordlists/common.txt
```

What you get: the full webapp pipeline (enum + robots + sitemap + crawler + nuclei + aquatone) limited to the given URL. Ideal for scopes restricted to a single application.

### 5.4. Full collector command

End-to-end pipeline — recon + web discovery + vhost + enumeration + crawler + vulnerability scan — in a single shot:

```bash
collector-docker -d example.com \
  --recon \
  --webapp-discovery --webapp-short-detection --vhost-validation \
  --webapp-enum --webapp-wordlists /opt/collector/wordlists/common.txt \
  --webapp-crawler \
  --webapp-scan
```

What you get: **every** artifact described in section 4, including `llm-prompt.txt`, an updated `<domain>_history.csv`, ingestion into `collector-results-db` and the dashboard running on `http://127.0.0.1:8000`. This is typically the command wired into cron/systemd (weekly) — the per-artifact diff ensures only changes hit the notification channel.

### 5.5. Reopening the dashboard without a new recon

At the end of every recon, `start_app_report` puts the Flask/gunicorn dashboard in the background so the operator has an interface ready to browse the results. Once that container exits (or the process is killed), the dashboard goes with it — but the data is preserved in the shared `outputs/` volume. To read it again without triggering another scan, use `--report-only`:

```bash
collector-docker --report-only        # foreground gunicorn on 127.0.0.1:8000, Ctrl-C stops
collector-docker --report-stop        # stop from another shell
```

`--report-only` requires a `collector-results-db` inside `outputs/` (it aborts with a clear message otherwise), refuses to start when another instance is already running (via pidfile + host-port probe), and is a strict read-only path — the Flask app opens the SQLite database with `mode=ro`. The wrapper names that container `collector-report` (override via `REPORT_CONTAINER_NAME=<name>` in the environment), which is what `--report-stop` targets on the host.

When the host port in `APP_PORT` (default `127.0.0.1:8000:8000`) is already bound — for instance because a previous recon left a background dashboard running, or a sibling container is publishing to it — `collector-docker` silently drops the `-p` flag from `docker run` rather than aborting with "port already allocated". The recon still completes, and the running dashboard already renders the new run's data because `outputs/` is shared.

### 5.6. Vhost-specific configuration (collector.cfg)

Vhost discovery has its own tuning section in `collector.cfg`. These variables only matter when `-vv|--vhost-validation` is used:

```bash
# vhost - performance tuning
vhost_check_processes=8            # parallel workers for vhost_check (curl+httpx per IP:port pair)
vhost_probe_processes=50           # parallel workers for vhost_probe (lightweight single curl each)
vhost_probe_batch_size=50          # words per worker in vhost_probe (reduces fork overhead)
vhost_port_detect=(80 443 8080 8443)  # ports for vhost brute (independent of webapp_port_detect)
vhost_connect_timeout=5            # curl connect timeout for vhost (seconds)
vhost_max_time=5                   # curl max-time for vhost (seconds)
vhost_prefilter_timeout=3          # TCP pre-filter timeout (seconds) — skips ports that don't respond
vhost_use_ffuf="no"                # use ffuf for vhost_probe instead of bash loop (yes/no)
vhost_ffuf_threads=50              # ffuf threads when enabled
```

Key behaviors controlled by these variables:

- **TCP pre-filter:** before brute-forcing a port, a fast TCP connect test (`vhost_prefilter_timeout`) discards ports that are closed — avoids thousands of wasted timeouts on the long port list.
- **Early-exit on dead baselines:** if the baseline request (random host) returns status `000` (connection refused), that (IP, port) pair is skipped entirely.
- **ffuf mode:** setting `vhost_use_ffuf=yes` replaces the Bash-loop probe with a single `ffuf` invocation per (IP, port) pair — orders of magnitude faster for large wordlists. Falls back to the Bash loop if `ffuf` is not in PATH.

## 6. Further details

For the full reference of every flag, the wrapper's environment variables (`COLLECTOR_IMAGE`, `OUTPUTS_DIR`, `WORDLISTS_DIR`, `COLLECTOR_CFG`, `APP_PORT`, `NOTIFY_CONFIG`), the `collector.cfg` parameters (timeouts, threads, port lists, API keys, Cloudflare quick-tunnel options), the cron/systemd templates, the `projectdiscovery/notify` integration, the SQLite schema and ready-made queries, **see the `README.md` in the collector repository**.

> **Warning:** collector generates a significant amount of traffic. Use only against targets you have explicit authorization to test.
