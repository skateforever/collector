# Usage manual — collector

## 1. What collector is and its focus as an offensive tool

`collector` is a Bash script that automates the reconnaissance and information-gathering phase during penetration tests and bug bounty engagements. It runs **exclusively inside a Docker container**, which isolates dependencies (Go, Python, Chromium, nmap, etc.) and guarantees each run starts from a clean, reproducible environment.

The offensive focus is to chain into a single pipeline the steps an attacker would normally execute manually at the start of an external-perimeter test:

- passive and active subdomain enumeration across ~30 OSINT sources (crt.sh, securitytrails, shodan, virustotal, alienvault, commoncrawl, dnsdumpster, rapiddns, hackertarget, whoisxmlapi, and others);
- target-infrastructure enrichment (ASN, IPv4/IPv6 blocks, DNS records, zone transfer);
- port scanning with nmap and Shodan;
- live HTTP(S) service discovery with `httpx` and vhost discovery (arbitrary `Host` header), two independent flags: `-vc|--vhost-check` (`vhost_check`, STRONG/WEAK confidence via curl+httpx) and `-vp|--vhost-probe` (`vhost_probe`, generic wordlist with reproducibility confirmation, requires `-vpw|--vhost-probe-wordlist`) — use either or both; confirmed hits from either auto-inject into the container's `/etc/hosts`;
- directory and file brute-force with `gobuster` + `dirsearch`, `robots.txt` and `sitemap.xml` capture, screenshots with `aquatone`;
- JS crawling with `katana` + `waybackurls`, de-obfuscation and pretty-printing of every downloaded bundle, parameter mining, sink classification (SQLi/XSS/SSRF/XXE/CMD), hardcoded-secret hunting (API keys, JWTs, tokens) and static reconstruction of the app's API surface into an OpenAPI 3.0 spec + Postman collection;
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
├── docker-compose.yaml                  ready-to-use service: volumes pre-configured,
│                                        -p needs -P|--service-ports with `run` (never automatic)
├── README.md                           full documentation
├── TODO.md                             internal roadmap
│
├── collector                           main Bash script (container entrypoint)
├── collector-docker                    host wrapper: injects -v always, -p only with --report-up,
│                                        plus `-i|--image` subcommands (update/pull/build-only/create/rm)
├── conf.d/                             config, split by concern:
│   ├── operation.conf                  runtime plumbing (colors, paths, DB, app-report)
│   ├── functions.conf                  per-tool parameters (timeouts, threads, port lists)
│   ├── apis-recon.conf.example         subdomain-discovery API keys (template, tracked)
│   ├── apis-recon.conf                 same, with real keys (gitignored)
│   ├── apis-emails.conf.example        email-recon API keys (template, tracked)
│   └── apis-emails.conf                same, with real keys (gitignored)
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
│   ├── app_report.sh                   Flask/gunicorn dashboard lifecycle (on-demand via --report-up, background or foreground)
│   ├── mcp_server.sh                   collector-mcp.py lifecycle (on-demand via --mcp-up/--shutdown, same background/foreground shape as app_report.sh)
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
│   └── js_scans.sh                     beautify_js_files + deobfuscate_js_files + scan_js_api + scan_js_secrets + scan_js_params
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
│   │   ├── schema/                     SQL schema for collector-results
│   │   └── scripts/                    js_deobfuscator.py (reverses JS obfuscation) +
│   │                                   js_api_extractor.py (reconstructs API calls into
│   │                                   OpenAPI 3.0 YAML + Postman Collection v2.1)
│   ├── docker/                         Docker configuration and volume strategy
│   │   ├── docker.env.template         template for environment variables (Docker Compose)
│   │   └── VOLUME_STRATEGY.md          detailed documentation on volumes (code replication)
│   ├── mcp/                            MCP server over collector-results — see MCP.md
│   │   ├── collector-mcp.py            read-only tools: targets, runs, artifacts, findings, diffs
│   │   ├── MCP.md                      setup, tool reference, container/host path rewrite
│   │   └── requirements.txt            mcp SDK (<2, FastMCP)
│   └── templates/                      drop-ins for automation
│       ├── cron/collector              daily/weekly cron
│       ├── systemd/collector@          systemd timer template
│       └── alerts-notify/              alert provider templates (Discord, Slack, Teams, Telegram, Signal)
│           ├── discord-provider.yaml
│           ├── slack-provider.yaml
│           ├── teams-provider.yaml
│           ├── telegram-provider.yaml
│           ├── signal-provider.yaml
│           ├── README.md               setup guide for each provider
│           └── MIGRATION.md            migration guide from legacy notify system
│
├── app-report/                         read-only dashboard (Flask + HTMX + gunicorn)
│   ├── app.py                          routes, reads collector-results
│   ├── db/                             volume (APP_REPORT_DB_DIR) — collector-results (SQLite)
│   ├── requirements.txt                flask, gunicorn
│   └── templates/                      index, target, runs, findings, diff, artifact, raw
│
└── demo/                               promo screenshots
```

## 3. Execution flow

The container entrypoint is the `collector` script. The flow is, in short:

1. **Bootstrap.** `collector` loads `functions/utils.sh` (banner, helpers, global-variable reset) and then `source`s `conf.d/operation.conf` and `conf.d/functions.conf` (required) followed by `conf.d/apis-recon.conf` and `conf.d/apis-emails.conf` — falling back to their `.example` templates if the real, gitignored files don't exist — to inherit timeouts, threads, short/long port lists and API keys.
2. **Module loading.** Every essential file under `functions/` (`menu.sh`, `usage.sh`, `check_*`, `domains_*`, `url_recon.sh`, `webapp_*`, `emails_recon.sh`, `git.sh`, `diff.sh`, `files.sh`, `infra.sh`, plus the app-report/dashboard modules `cloudflare_tunnel.sh`, `app_report.sh`, `mcp_server.sh`, `db_usage.sh`, `llm_prompt.sh`) and `scans/` (`acunetix.sh`, `nmap.sh`, `nuclei.sh`, `shodan.sh`, `js_scans.sh`) is sourced in sequence.
3. **Validation.** `check_container` confirms execution is happening inside Docker (the script aborts otherwise); `check_binaries` validates the presence of the required tools in PATH.
4. **CLI parsing.** `menu "$@"` processes the flags (`-d`, `-dl`, `-u`, `-r`, `-wd`, `-we`, `-ws`, `-wc`, `-vc`, `-dr`, etc.). `validate_domain` applies a strict regex to each target. With no arguments, `usage` is shown.
5. **Coherence.** `check_execution` validates invalid flag combinations, `check_parameter_conflicts` rejects mutually exclusive ones, `check_directory_permission` ensures `/opt/collector/outputs` is writable.
6. **Per-target lock.** `collector_acquire_lock "${domain}"` uses `flock` to prevent concurrent runs against the same domain (so the `*_diff.txt` artifacts stay consistent).
7. **Directory tree.** `create_directory_structure` builds `outputs/<domain>/recon_YYYYMMDD/{log,tmp,report/{scan/{nmap,nuclei,shodan},webapp/{aquatone,enum,javascript,params,tech}}}`. In "reuse" mode (running `-we`/`-ws`/`-wc` without `-r`), it picks the most recent recon_dir that has a `domains_alive.txt`.
8. **Dry-run exit.** If `-dr` (or `--dry-run`) is passed, the script prints a pre-flight summary (target, IPv4 regex, timeouts, wordlists, port list, proxy, Shodan) and exits 0 without executing recon.
9. **Mode routing.** `domains_recon` (for `-d`/`-dl`) or `url_recon` (for `-u`) decides which subset of the pipeline to execute based on the flags present. The full happy-path for `-d --recon --webapp-discovery --vhost-check --vhost-probe --vhost-probe-wordlist <file> --webapp-enum --webapp-crawler --webapp-scan` is:
   1. `subdomains_recon` — fans out all `sources/` modules in parallel (OSINT APIs + optional DNS bruteforce + amass/subfinder/tlsx);
   2. `joining_subdomains` — `files.sh` consolidates every raw output under `tmp/` into a single deduplicated `domains_found.txt` filtered to the root domain;
   3. `diff_domains` — produces `domains_diff.txt` (delta vs. previous run);
   4. `organizing_subdomains` — splits into `domains_alive.txt` (DNS-resolving) vs. `domains_without_resolution.txt` (vhost candidates), builds `domains_aliases.txt`, `domains_thirdpart.txt`, `domains_excluded.txt`;
   5. `infra_data` — collects ASN, IP blocks, IPv4/IPv6 (internal vs. external), attempts a zone transfer;
   6. `asn_sweep` + `ptr_sweep` — sweep the ASN/netblock and reverse `/24` (PTR) of **every** infrastructure IP in `infra_ipv4.txt` (not just the root domain's own IP, like before); dedup by ASN/block plus a safety cap (`asn_max_targets`/`ptr_max_blocks`) keep this from ballooning the run time. Since `joining_subdomains` already ran (step 2), fresh hits get merged straight into `domains_found.txt` and re-resolved right here, the same pattern `spider_src` uses;
   7. `nmap_scan` + `shodan_scan` — port scan on the external IP set;
   8. `webapp_alive` — `httpx` against `domains_alive.txt` across the port list (`webapp_http_ports` with `-wsd`; the full `webapp_http_ports`+`webapp_tls_ports`+`webapp_multiple_ports` union with `-wld`; or just the `webapp_http_ports`+`webapp_tls_ports` union with `-wcp`);
   9. `vhost_check` **(only when `-vc|--vhost-check` is passed)** + `vhost_probe` **(only when `-vp|--vhost-probe` is passed, requires `-vpw|--vhost-probe-wordlist`)** — two independent gates, use either or both, to discover vhosts served by external IPs. `vhost_check` tests candidates with prior evidence (curl+httpx, classifies STRONG/WEAK); `vhost_probe` tests a generic wordlist with no prior evidence (single-tool, confirms via reproducibility). Confirmed hits from either — STRONG from `vhost_check`, or any confirmed `vhost_probe` hit — write into `etc_hosts_file.txt` and get injected into the container's `/etc/hosts` so every downstream tool resolves them transparently, with or without public DNS. `vhost_check` WEAK stays in `vhost_subdomains_weak.txt` only, for manual review. When `vhost_use_ffuf=yes` in `conf.d/functions.conf`, `vhost_probe` delegates to `ffuf` for significantly faster wordlist-based discovery;
   10. `build_consolidated_urls` — produces `webapp_consolidated.txt` (every live HTTP(S) URL, DNS + STRONG vhosts);
   11. `webapp_tech` — captures response headers for fingerprinting (in `report/webapp/tech/`);
   12. `emails_recon` — Hunter.io + IntelX (phonebook target=2) + Lampyre + Snov.io + page/JS crawl of the consolidated list;
   13. `crawler_js` + `crawler_params` — katana + waybackurls extract JS and parameters and recursively expand `sitemap.xml`. `crawler_js` then runs every downloaded `.js` through a post-process chain: `beautify_js_files` pretty-prints it and moves it to `<name>.beautify.js` (kept as a permanent audit copy, still obfuscated); `deobfuscate_js_files` reverses hex/unicode escapes, base64, the Dean Edwards packer and javascript-obfuscator's string-array encoding, creating the final `<name>.js` from that copy; `scan_js_api` reconstructs the app's API calls (method/url/body) into a text report, an OpenAPI 3.0 YAML and a Postman Collection v2.1; `scan_js_secrets` searches the de-obfuscated JS for hardcoded secrets. `crawler_params` then classifies discovered parameters by sink (`scan_js_params`);
   14. `nuclei_scan` — vulnerability scan against the consolidated list;
   15. `webapp_enum` — gobuster + dirsearch against the consolidated list, `robots.txt`, `sitemap.xml`; `aquatone_screenshot` for each batch; `git_rebuild` (git-dumper) if exposed `.git/` directories are found;
   16. `diff_artifacts` — generates `*_diff.txt` for each relevant artifact;
   17. `build_llm_prompt` — concatenates every artifact into `llm-prompt.txt` with an instruction header;
   18. `record_history` — appends a row to `<domain>_history.csv` (trend log);
   19. `db_usage` — idempotent upsert of the run into `collector-results` (SQLite, WAL, FKs);
   20. `start_app_report` — starts (or reuses) gunicorn on port 8000; optionally brings up a Cloudflare tunnel if `cloudflare_tunnel="yes"`;
   21. `message "${domain}" finished` — sends a final notification via `notify` (Slack/Discord/Telegram/etc., per `provider-config.yaml`).

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
`report/etc_hosts_file.txt` — `ip<TAB>hostname` map injected into the container's `/etc/hosts`. Carries `vhost_check` **STRONG** hits **and** confirmed `vhost_probe` hits (same bar: cleared the multi-sample baseline + reproducibility check). `vhost_check` WEAK never lands here — it's single-tool confidence (curl and httpx disagree), not dual.
`report/vhost_subdomains_strong.txt` / `vhost_subdomains_weak.txt` / `vhost_subdomains_diff.txt` — `vhost_check` hits, classified by confidence (STRONG = curl and httpx agree; WEAK = only one of them does) plus the STRONG delta between runs. WEAK is deliberately kept out of the automated pipeline — never injected into `/etc/hosts`, never feeds `webapp_consolidated.txt` — but is persisted for manual review instead of being computed and thrown away.
`report/vhost_probe_hits.txt` — confirmed `vhost_probe` hits, in the same layout as `vhost_subdomains_strong/weak.txt` (`scheme://host<TAB>ip:port<TAB>Size: N<TAB>Hash: X<TAB>tag`), with the tag always `CONFIRMED` — no real confidence tier (single-tool, no curl+httpx consensus to split on — it's either confirmed by reproducibility or it isn't in this file). Also feeds `etc_hosts_file.txt`/`vhost_urls.txt`, so it's testable even without public DNS.
`report/robots_urls.txt` — URLs extracted from the harvested `robots.txt` files.
`report/sitemap_urls.txt` — URLs harvested recursively from `sitemap.xml`/`sitemapindex`.
`report/webapp_js_secrets.txt` — secrets, tokens, JWTs and API keys found in the de-obfuscated JS.
`report/webapp_js_params.txt` — discovered parameters + sink classification (SQLi, XSS, SSRF, XXE, CMD, etc.).
`report/webapp_js_api.txt` — API calls (method/url/body) reconstructed from the JS, as raw source text — a static best-effort for manual triage, never a resolved/verified value.
`report/webapp_js_api_openapi.yaml` — the same reconstructed calls as an OpenAPI 3.0 document; every operation carries an `x-source` extension pointing back at the file:line it came from.
`report/webapp_js_api_postman_collection.json` — the same reconstructed calls as a Postman Collection v2.1, with the target as a `{{baseUrl}}` collection variable — import and run with no setup.

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
`report/webapp/javascript/` — one `<name>.js` (de-obfuscated, final) + `<name>.beautify.js` (pretty but still obfuscated, permanent audit copy) per downloaded file. `<name>.js` is the input for `webapp_js_secrets`/`webapp_js_params`/`webapp_js_api`; `*.beautify.js` is excluded from all three.
`report/webapp/params/` — raw katana and waybackurls output.
`report/webapp/tech/` — response headers for fingerprinting (Server, X-Powered-By, etc.).

### Synthesis and persistence
`report/llm-prompt.txt` — single bundle with every artifact above plus an instruction header; ready to paste into any LLM for follow-up analysis.
`<domain>_history.csv` (inside this `report/`) — one row per run, feeds the trend view in the dashboard.
`app-report/db/collector-results` (its own volume, `APP_REPORT_DB_DIR`) — SQLite with `targets(domain PK)` + `recon_runs(domain, run_id, ...)` + `latest_run` view. Idempotent: re-running the same `run_id` only writes when the payload changes.

## 5. How to run collector

### 5.0. Keeping collector up to date

`collector-docker --image <subcommand>` automates pulling changes and rebuilding the Docker image **only when necessary**:

```bash
./collector-docker --image update              # git pull + conditional rebuild
./collector-docker --image pull                # git pull without building
./collector-docker --image build-only          # rebuild without pulling
./collector-docker --image update --force-build # rebuild even if no structural changes
./collector-docker --image create              # full clean rebuild: --no-cache --pull, ignores git
./collector-docker --image rm                  # remove the local image (docker rmi)
./collector-docker --image rm --force          # force removal even if a stopped container references it
```

The `update`/`pull` subcommands inspect changed files and only trigger an image rebuild when **structural files** change (Dockerfiles, `functions/check_binaries.sh`). Script-only changes are served instantly via volume mounts in `collector-docker`, so no rebuild is needed. `create` always rebuilds from scratch, ignoring both git and Docker's build cache. `rm` (alias `remove`) just deletes the local image.

Optional: install the `post-merge` git hook to auto-rebuild after every `git pull`:

```bash
git config core.hooksPath support/templates/githooks
# Now git pull automatically triggers rebuild when structural files change (via collector-docker --image build-only)
```

**Important note:** `collector-docker` mounts scripts (`collector`, `functions/`, `scans/`, `sources/`, `support/runtime/`) as read-only volumes from the host. This means code changes are instantly available without rebuilding the Docker image. The image only needs rebuilding when binaries or system packages change.

### 5.1. Pre-flight validation (dry run)

Before kicking off a long-running pipeline, use `-dr` (or `--dry-run`) to validate that config, locks, and directory permissions are in order:

```bash
collector-docker -d example.com --recon --webapp-discovery --webapp-short-detection -dr
```

This executes every pre-flight check (CLI parsing, domain validation, directory creation, lock acquisition) and prints a summary of resolved parameters. It exits 0 on success without generating any traffic.

The examples below use the `collector-docker` wrapper exclusively, which automatically injects the volumes (`outputs`, `wordlists`, `conf.d/`) — and `-p 127.0.0.1:8000:8000`, but **only** when `-ru|--report-up` is present (the dashboard never starts otherwise, see §5.5). Running collector via a bare `docker run`/`docker compose` instead is possible — `collector` is, underneath, just a container entrypoint — but means hand-managing every volume, the dashboard port, and container naming/lifecycle yourself, which is exactly the bookkeeping `collector-docker` exists to remove; this guide no longer shows that path, since mismatched hand-assembled flags were the most common source of dashboard confusion reported.

### 5.2. Basic reconnaissance commands

Pure recon — only discovers subdomains, infra, ASN, IPs and runs nmap/Shodan. No HTTP traffic:

```bash
collector-docker -d example.com --recon
```

What you get: `domains_found.txt`, `domains_alive.txt`, `domains_without_resolution.txt`, `infra_*.txt`, `scan/nmap/nmap_scan.txt`, `scan/shodan/shodan_scan.txt`, `email_recon.txt`. A good first step to map the perimeter without generating noisy HTTP traffic.

Recon + web application discovery using the fixed-plain-HTTP port list (defined in `conf.d/functions.conf` as `webapp_http_ports`):

```bash
collector-docker -d example.com --recon --webapp-discovery --webapp-short-detection
```

What you get: everything from the previous command plus `webapp_consolidated.txt` (live HTTP(S) URLs) and `webapp/tech/` with fingerprinting headers. This is the typical entry point for any new target. **Note:** vhost discovery (`vhost_subdomains_strong.txt`, `etc_hosts_file.txt`) requires adding `-vc|--vhost-check` and/or `-vp|--vhost-probe` (the latter also needs `-vpw|--vhost-probe-wordlist`) — two independent flags, see below.

Recon + web application discovery **with vhost validation** (both `-vc` and `-vp` — either works alone too):

```bash
collector-docker -d example.com --recon --webapp-discovery --webapp-short-detection \
  --vhost-check --vhost-probe --vhost-probe-wordlist /opt/collector/support/runtime/wordlists/vhost-probe-names.txt
```

What you get: everything above plus `vhost_subdomains_strong.txt`, `vhost_subdomains_weak.txt` (from `-vc`), `vhost_probe_hits.txt` (from `-vp`), `etc_hosts_file.txt`. `vhost_check` probes every IP in `infra_ipv4.txt` using dual-tool (curl + httpx) cross-validation; `vhost_probe` tests a generic wordlist with a single tool (or `ffuf`, if enabled), confirming via reproducibility. STRONG (vhost_check) and any confirmed hit (vhost_probe) get injected into `/etc/hosts` and feed `webapp_consolidated.txt`; WEAK (vhost_check) is persisted for manual review only.

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

What you get: `webapp/javascript/` (de-obfuscated JS as `<name>.js`, plus the still-obfuscated `<name>.beautify.js` audit copy), `webapp/params/` (katana + waybackurls output), `webapp_js_secrets.txt` (hardcoded keys/tokens/JWTs), `webapp_js_params.txt` (parameters with sink classification), `webapp_js_api.txt` + `webapp_js_api_openapi.yaml` + `webapp_js_api_postman_collection.json` (the app's API calls reconstructed from the JS — import the Postman collection directly, or the OpenAPI spec into any client). Focus on finding injection vectors and mapping the API surface for the exploitation phase.

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
  --webapp-discovery --webapp-short-detection \
  --vhost-check --vhost-probe --vhost-probe-wordlist /opt/collector/support/runtime/wordlists/vhost-probe-names.txt \
  --webapp-enum --webapp-wordlists /opt/collector/wordlists/common.txt \
  --webapp-crawler \
  --webapp-scan
```

What you get: **every** artifact described in section 4, including `llm-prompt.txt`, an updated `<domain>_history.csv`, and ingestion into `collector-results`. Add `--report-up` to this command if you also want the dashboard up afterward (see below) — it's typically left off for the cron/systemd (weekly) invocation, where only the per-artifact diff needs to hit the notification channel.

### 5.5. The dashboard — on-demand only, via `--report-up`

The dashboard never starts on its own. `collector` runs as the container's PID 1, so a dashboard merely left running in the background would be killed the instant the recon finishes and PID 1 exits — the kernel tears down the whole PID namespace the moment its init process dies, independent of `docker run --rm`. So the dashboard only ever comes up when `-ru|--report-up` is explicitly passed, and when it is, the container itself stays alive (detached, no `--rm`, port published) for exactly as long as the dashboard should keep serving:

```bash
# Dashboard alone, reading an earlier scan's results (no new recon):
collector-docker --report-up          # detached, http://127.0.0.1:8000, persists until stopped
collector-docker --shutdown           # stop from another shell

# Or combined with a fresh recon, same container:
collector-docker -d example.com --recon --report-up
collector-docker --shutdown           # stop when done
```

`--report-up` alone requires a `collector-results` inside `app-report/db/` (it aborts with a clear message otherwise, before even starting a container); combined with a recon, that recon is what creates the DB, so no such preflight applies. Either way it refuses to start when another instance is already running (via container-name collision + pidfile), and the dashboard itself is a strict read-only path — the Flask app opens the SQLite database with `mode=ro`. The wrapper names the container `collector-reconnaissance` (override via `COLLECTOR_CONTAINER_NAME=<name>` in the environment), which is what `--shutdown` targets on the host regardless of which of the two forms above started it (and regardless of whether the MCP server is also running there — see 5.6 below).

`--shutdown` must be used alone — passing any other flag alongside it (a target flag, `--report-up`, anything) is rejected with a usage error instead of silently ignored. This is checked twice: by `collector-docker` on the host (before it even touches Docker) and by `collector` itself inside the container (so the rule holds even if you call `collector` directly, bypassing the wrapper).

Without `--report-up`, nothing changes from a plain recon invocation: the container runs attached, uses `--rm`, and the dashboard port is never published — there's no dashboard to reach either way, so publishing the port would be pointless. When `--report-up` *is* passed and the host port is already bound, `collector-docker` now fails fast with a clear message instead of silently dropping the `-p` flag — a persistent, `--rm`-less container that never actually published its port would otherwise sit there uselessly.

Every setting that affects dashboard exposure lives in `conf.d/operation.conf` — `collector-docker` reads it rather than hardcoding its own values, falling back to a hardcoded `127.0.0.1`/`8000` only as a last resort, if that file can't be found or read at all. The port itself is configured once, via `app_report_container_port` (default `8000`) — `collector-docker` reads that same file to build the `-p` mapping it publishes, so changing `app_report_container_port` is enough on its own: gunicorn inside the container and the published port always agree. The published address is a separate setting, `app_report_host_address` (default `127.0.0.1`, i.e. not reachable from other machines) — this is the one setting that controls whether another machine can reach the dashboard; set it to the machine's LAN/public IP, or `0.0.0.0` for every interface, to reach the dashboard from elsewhere — the printed URL always uses this same value, so it stays reachable from where you're opening it automatically. `app_report_container_address` in the same file is a different, container-internal setting (gunicorn's own bind address inside the container's network namespace) and does not need to change for this. `APP_REPORT_HOST_ADDRESS`/`APP_REPORT_HOST_PORT` environment variables exist only to override these for a single `collector-docker` invocation, taking priority over `conf.d/operation.conf` when set. `docker-compose.yaml` can't execute shell logic to read `conf.d/operation.conf`, so its `ports:` line carries the same `127.0.0.1`/`8000` fallback baked directly into the YAML (`${APP_REPORT_HOST_ADDRESS:-127.0.0.1}:${APP_REPORT_CONTAINER_PORT:-8000}`) — kept in sync with `operation.conf` by hand via `.env`, not read from it.

Note that `--report-up` names a single fixed container (`COLLECTOR_CONTAINER_NAME`, default `collector-reconnaissance`) and publishes a single fixed port — it's meant to run once, not multiple times in parallel. Running several recons at once against different domains is fine without `--report-up` (per-target lock + anonymous containers + a WAL-mode results DB make that safe); bring up one shared dashboard afterward to see all of them together.

### 5.6. The MCP server — on-demand only, via `--mcp-up`

`support/mcp/collector-mcp.py` (see `support/mcp/MCP.md`) exposes collector's results as MCP tools for an agent client. Normally an MCP client (Claude Desktop/Code) launches it itself over stdio — nothing in `collector`'s own CLI is involved. `-mu|--mcp-up` adds a second way to run it: as a long-lived `streamable-http` service managed exactly like the dashboard, for a client on another machine or just to keep it running independently of any one client's lifecycle.

`functions/mcp_server.sh` mirrors `functions/app_report.sh` point for point — same background/foreground dual-mode `run_mcp_server()`, same shared pidfile (`support/mcp/run/collector-mcp.pid`, mounted via `MCP_RUN_DIR`) so `--shutdown` can stop either launch mode, same `/proc/<pid>/cmdline` disambiguation to avoid mistaking container PID 1 for a stale pidfile's process, same SIGTERM→wait 5s→SIGKILL stop:

```bash
# MCP server alone:
collector-docker --mcp-up             # detached, http://127.0.0.1:8010, persists until stopped
collector-docker --shutdown           # stop from another shell

# Or combined with a fresh recon, same container, after --report-up's own dashboard if both are passed:
collector-docker -d example.com --recon --report-up --mcp-up
collector-docker --shutdown           # stops the whole container (both services)
```

One hard requirement unique to `--mcp-up`: `collector_mcp_transport` in `conf.d/operation.conf` must already be `"streamable-http"`, not the default `"stdio"` — stdio is a per-client subprocess with no network port, nothing for a background/foreground service to bind. `--mcp-up` refuses to start with a clear message naming the fix, checked both by `collector-docker` on the host (before touching Docker) and by `collector` itself inside the container (functions/mcp_server.sh's `run_mcp_server()`).

`--mcp-up` and `--report-up` share the SAME persistent container and name (`COLLECTOR_CONTAINER_NAME`) when both are passed — one container publishing both ports, not two containers. `--shutdown` always stops the whole container, both services included, whichever of the two (or both) happen to be running there — there is no narrower "stop just one service" mode (an earlier design had `--mcp-down` reach into the container surgically via `docker exec` while leaving app-report running; that asymmetry was removed in favor of one single "stop everything" flag, matching what `docker stop` already does). `collector`'s own SIGTERM trap calls `stop_app_report` and `stop_mcp_server` first, so this is graceful, not a kernel SIGKILL.

When combined with a recon target, ordering matters: `start_app_report` always runs before `start_mcp_server` at the tail of `domains_recon`/`url_recon` (see `functions/domains_recon.sh`/`functions/url_recon.sh`), so the dashboard's "is up" line reads before the MCP server's, regardless of which flag was typed first on the command line.

`--report-up --mcp-up` passed together with no target flag is handled specially in `collector`: both services start in the **background**, and `collector` holds the process open afterward (`_collector_hold_for_dashboard` + `_collector_hold_for_mcp_server`) rather than `exec`-replacing itself with either service in the foreground — there's no way to `exec`-replace PID 1 with two programs at once, so running both requires this background+hold shape regardless of how `--shutdown` stops them later.

### 5.7. Vhost-specific configuration (conf.d/functions.conf)

Vhost discovery has its own tuning section in `conf.d/functions.conf`. `vhost_baseline_samples`/`vhost_connect_timeout`/`vhost_max_time`/`vhost_prefilter_timeout` are shared by both tools; `vhost_check_*` only matters with `-vc|--vhost-check`, `vhost_probe_*`/`vhost_use_ffuf` only with `-vp|--vhost-probe`:

```bash
# vhost - performance tuning
vhost_baseline_samples=3           # independent samples (random host each) making up the "no such vhost" baseline
vhost_check_processes=16           # parallel workers for vhost_check (each worker runs one batch of names)
vhost_check_batch_size=20          # names per vhost_check worker (curl+httpx per name, hence smaller than the probe's)
vhost_probe_processes=50           # parallel workers for vhost_probe (lightweight single curl each)
vhost_probe_batch_size=50          # words per worker in vhost_probe (reduces fork overhead)
vhost_connect_timeout=5            # curl connect timeout for vhost (seconds)
vhost_max_time=5                   # curl max-time for vhost (seconds)
vhost_prefilter_timeout=3          # TCP pre-filter timeout (seconds) — skips ports that don't respond
vhost_use_ffuf="no"                # use ffuf for vhost_probe instead of bash loop (yes/no)
vhost_ffuf_threads=50              # ffuf threads when enabled
```

There is no vhost-specific port list: `vhost_check`/`vhost_probe` always use `webapp_port_detect` — the same list set by whichever webapp-detection flag the run picked (`-wsd`/`-wcp`/`-wld`).

Key behaviors controlled by these variables:

- **TCP pre-filter:** before brute-forcing a port, a fast TCP connect test (`vhost_prefilter_timeout`) discards ports that are closed — avoids thousands of wasted timeouts on the long port list.
- **Early-exit on dead baselines:** if every baseline sample (random host) returns status `000` (connection refused), that (IP, port) pair is skipped entirely.
- **Multi-sample baseline:** a single sample can't tell a stable default response apart from one draw of a page that varies per request (CSRF token, timestamp, request id) — in the latter case every candidate would look "different" from that one snapshot, flooding the output with false positives. `vhost_baseline_samples` samples (random host each) form a set instead; a candidate only counts as different if it matches **none** of the samples in that set, and is still re-probed once more (same question, same host) before being reported — a genuine vhost reproduces the same answer; noise usually doesn't.
- **ffuf mode:** setting `vhost_use_ffuf=yes` replaces the Bash-loop probe with a single `ffuf` invocation per (IP, port) pair — orders of magnitude faster for large wordlists. `-fs` gets the comma-separated size list from every baseline sample, and each candidate that clears ffuf's filter is still re-verified (size + hash + reproducibility) before making it into the result. Falls back to the Bash loop if `ffuf` is not in PATH.

## 6. Further details

For the full reference of every flag, the wrapper's environment variables (`COLLECTOR_IMAGE`, `OUTPUTS_DIR`, `WORDLISTS_DIR`, `APP_REPORT_DB_DIR`, `CONF_D_DIR`, `APP_REPORT_HOST_ADDRESS`, `APP_REPORT_HOST_PORT`, `NOTIFY_CONFIG`), the `conf.d/*.conf` parameters (timeouts, threads, port lists, API keys, Cloudflare quick-tunnel options), the cron/systemd templates, the `projectdiscovery/notify` integration, the SQLite schema and ready-made queries, **see the `README.md` in the collector repository**.

> **Warning:** collector generates a significant amount of traffic. Use only against targets you have explicit authorization to test.
