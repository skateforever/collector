## collector

collector is a Bash script that automates reconnaissance and information gathering during penetration tests and bug bounty hunting. It runs **exclusively inside a Docker container**.

## Quick start

Build the image once:

```bash
docker build -t collector:latest /opt/collector
```

Run a full recon + webapp discovery:

```bash
# docker run
docker run --rm \
  -v /opt/collector/outputs:/app/outputs \
  -v /opt/collector/wordlists:/app/wordlists \
  -v /opt/collector/collector.cfg:/app/collector.cfg:ro \
  collector:latest -d example.com --recon --webapp-discovery --webapp-short-detection

# docker compose (from repo root)
docker compose run --rm collector -d example.com --recon --webapp-discovery --webapp-short-detection

# collector-docker wrapper
collector-docker -d example.com --recon --webapp-discovery --webapp-short-detection
```

Results are written to `/opt/collector/outputs/example.com/recon_YYYYMMDD/`.

## Execution methods

There are three equivalent ways to run collector — all produce the same results.

**`docker run`** — explicit, no setup required beyond building the image. You must pass `-v` and optionally `-p` on every invocation.

**`docker compose`** — volumes and port mapping are pre-configured in `docker-compose.yml`. Run from the repo root. Useful when overriding build args or pinning the image.

**`collector-docker`** — thin wrapper around `docker run` that injects volumes and the default port mapping automatically. Install it once and use it like a native command:

```bash
sudo install -m 0755 /opt/collector/collector-docker /usr/local/bin/collector-docker
```

Override defaults via environment variables:

| Variable | Default |
|----------|---------|
| `COLLECTOR_IMAGE` | `collector:latest` |
| `OUTPUTS_DIR` | `/opt/collector/outputs` |
| `WORDLISTS_DIR` | `/opt/collector/wordlists` |
| `COLLECTOR_CFG` | `/opt/collector/collector.cfg` |
| `APP_PORT` | `127.0.0.1:8000:8000` |

## Command reference

### Target selection (required — pick one)

| Flag | Description |
|------|-------------|
| `-d \| --domain <domain>` | Single target domain. |
| `-dl \| --domain-list <file>` | File with one domain per line (`#` for comments). |
| `-u \| --url <url>` | Single URL — skips infra/subdomain recon, runs webapp enum only. |

### Recon

| Flag | Description |
|------|-------------|
| `-r \| --recon` | Passive + active subdomain discovery, DNS, infra enrichment (AS/IPs/netblocks), nmap, Shodan. Entry point for any new target. |

### Webapp discovery (requires `--recon` or existing `domains_alive.txt`)

| Flag | Description |
|------|-------------|
| `-wd \| --webapp-discovery` | Probes live hosts for active HTTP(S) services, runs vhost discovery, builds `webapp_consolidated.txt`. |
| `-wsd \| --webapp-short-detection` | Uses the short port list from `collector.cfg` (`web_port_short_detection`). Use with `-wd`. |
| `-wld \| --webapp-long-detection` | Uses the long port list from `collector.cfg` (`web_port_long_detection`). Use with `-wd`. |

### Webapp enumeration (requires existing `webapp_consolidated.txt` or combined with `--webapp-discovery`)

| Flag | Description |
|------|-------------|
| `-we \| --webapp-enum` | Directory and file brute-force with gobuster + dirsearch, robots.txt extraction, aquatone screenshots. |
| `-ww \| --webapp-wordlists <file[,file]>` | Extra wordlists for `-we`. |
| `-l \| --limit-urls <n>` | Limit enumeration to the top N URLs (used with `-d`). |

### Webapp crawler

| Flag | Description |
|------|-------------|
| `-wc \| --webapp-crawler` | Crawls JS files with katana and mines URL parameters with waybackurls. |

### Webapp scan

| Flag | Description |
|------|-------------|
| `-ws \| --webapp-scan` | Nuclei scan against `webapp_consolidated.txt`. |

### Subdomain brute-force (optional, used with `--recon`)

| Flag | Description |
|------|-------------|
| `-s \| --subdomain-brute <file[,file]>` | Additional wordlists for DNS brute-force via gobuster + dnssearch. |

### Scope filtering

| Flag | Description |
|------|-------------|
| `-ed \| --exclude-domain <d1,d2>` | Comma-separated subdomains to exclude from results. Used with `-d`. |
| `-el \| --exclude-domain-list <file>` | File of subdomains to exclude. Used with `-d` or `-dl`. |

### Process control

| Flag | Description |
|------|-------------|
| `-k \| --kill <domain>` | Kill a running collector for the given domain. |
| `-kr \| --kill-remove <domain>` | Kill and delete the current run directory for the given domain. |

## Common usage patterns

Full recon + webapp discovery (short port list):

```bash
docker run --rm \
  -v /opt/collector/outputs:/app/outputs \
  -v /opt/collector/wordlists:/app/wordlists \
  -v /opt/collector/collector.cfg:/app/collector.cfg:ro \
  collector:latest \
  -d example.com --recon --webapp-discovery --webapp-short-detection

docker compose run --rm collector \
  -d example.com --recon --webapp-discovery --webapp-short-detection

collector-docker -d example.com --recon --webapp-discovery --webapp-short-detection
```

Full recon + webapp discovery + enum + scan in one shot:

```bash
docker run --rm \
  -v /opt/collector/outputs:/app/outputs \
  -v /opt/collector/wordlists:/app/wordlists \
  -v /opt/collector/collector.cfg:/app/collector.cfg:ro \
  collector:latest \
  -d example.com --recon --webapp-discovery --webapp-short-detection \
  --webapp-enum --webapp-wordlists /app/wordlists/common.txt --webapp-scan

docker compose run --rm collector \
  -d example.com --recon --webapp-discovery --webapp-short-detection \
  --webapp-enum --webapp-wordlists /app/wordlists/common.txt --webapp-scan

collector-docker -d example.com --recon --webapp-discovery --webapp-short-detection \
  --webapp-enum --webapp-wordlists /app/wordlists/common.txt --webapp-scan
```

Standalone webapp enum on a previously recon'd target:

```bash
docker run --rm \
  -v /opt/collector/outputs:/app/outputs \
  -v /opt/collector/wordlists:/app/wordlists \
  -v /opt/collector/collector.cfg:/app/collector.cfg:ro \
  collector:latest \
  -d example.com --webapp-enum --webapp-wordlists /app/wordlists/common.txt

docker compose run --rm collector \
  -d example.com --webapp-enum --webapp-wordlists /app/wordlists/common.txt

collector-docker -d example.com --webapp-enum --webapp-wordlists /app/wordlists/common.txt
```

Standalone webapp scan on a previously recon'd target:

```bash
docker run --rm \
  -v /opt/collector/outputs:/app/outputs \
  -v /opt/collector/wordlists:/app/wordlists \
  -v /opt/collector/collector.cfg:/app/collector.cfg:ro \
  collector:latest \
  -d example.com --webapp-scan

docker compose run --rm collector -d example.com --webapp-scan

collector-docker -d example.com --webapp-scan
```

Standalone JS crawler:

```bash
docker run --rm \
  -v /opt/collector/outputs:/app/outputs \
  -v /opt/collector/wordlists:/app/wordlists \
  -v /opt/collector/collector.cfg:/app/collector.cfg:ro \
  collector:latest \
  -d example.com --webapp-crawler

docker compose run --rm collector -d example.com --webapp-crawler

collector-docker -d example.com --webapp-crawler
```

List of targets:

```bash
docker run --rm \
  -v /opt/collector/outputs:/app/outputs \
  -v /opt/collector/wordlists:/app/wordlists \
  -v /opt/collector/collector.cfg:/app/collector.cfg:ro \
  collector:latest \
  -dl /app/outputs/targets.list --recon --webapp-discovery --webapp-short-detection

docker compose run --rm collector \
  -dl /app/outputs/targets.list --recon --webapp-discovery --webapp-short-detection

collector-docker -dl /app/outputs/targets.list --recon --webapp-discovery --webapp-short-detection
```

Single URL (no subdomain/infra discovery):

```bash
docker run --rm \
  -v /opt/collector/outputs:/app/outputs \
  -v /opt/collector/wordlists:/app/wordlists \
  -v /opt/collector/collector.cfg:/app/collector.cfg:ro \
  collector:latest \
  -u https://app.example.com --webapp-wordlists /app/wordlists/common.txt

docker compose run --rm collector \
  -u https://app.example.com --webapp-wordlists /app/wordlists/common.txt

collector-docker -u https://app.example.com --webapp-wordlists /app/wordlists/common.txt
```

## Unattended execution

Drop-in scheduling files are in `support/`:

- `collector-cron` — daily light recon + weekly heavy run via cron (`/etc/cron.d/collector`)
- `collector-systemd-timer` — same cadence as systemd template units (`collector@<domain>.timer`)

Both use `collector-docker` (or `docker run --rm` directly) — each run fires an ephemeral container. Results persist via the `/app/outputs` volume. Per-target `flock` prevents overlapping runs for the same domain when triggered by cron or timers.

## APIs and tools used

**Subdomain sources:** alienvault, builtwith, certspotter, commoncrawl, crt.sh, dnsdumpster, hackertarget, rapiddns, securitytrails, shodan, virustotal, webarchive, whoisxmlapi

**Recon tools:** amass, dnssearch, gobuster, subfinder, tlsx, waybackurls

**Infrastructure:** nmap, shodan

**Webapp discovery:** httpx, chromium

**Webapp enumeration:** dirsearch, gobuster, git-dumper

**Webapp crawler:** katana, waybackurls

**Webapp scan:** nuclei

**Screenshots:** aquatone

**Email recon:** Hunter.io, Lampyre, Snov.io (API-based) + page/JS crawl of `webapp_consolidated.txt`

**Reporting:** sqlite3, Flask, gunicorn, HTMX

## Main features

- Per-run dated folder (`recon_YYYYMMDD`) with logs, tmp, and structured report tree
- Subdomain discovery via passive sources + active DNS bruteforce
- Infrastructure enrichment: AS / IPv4 / IPv6 / netblocks / nmap / Shodan
- vhost discovery: parallel curl + httpx probing, STRONG vs. WEAK confidence classification, automatic `/etc/hosts` injection inside the container so all tools resolve vhosts transparently
- Per-artifact diff vs. previous run — only deltas pushed to notify channel
- Email harvesting from APIs + page/JS crawl filtered to the target domain
- JS scraping and parameter mining with sink classification (SQLi/XSS/SSRF/XXE/CMD/...)
- Two LLM prompt bundles per run: `llm-local-prompt.txt` (webapp_consolidated + etc_hosts only) and `llm-claude-prompt.txt` (all artifacts) — ready to paste into any LLM for follow-up analysis
- SQLite ingestion: each run upserted into `collector-results-db` (idempotent, WAL, FK-protected)
- Flask + HTMX read-only web UI at `http://127.0.0.1:8000` auto-started after each run
- Cloudflare quick-tunnel (opt-in via `cloudflare_tunnel="yes"` in `collector.cfg`) for remote dashboard access
- Per-target flock so concurrent runs for the same domain abort instead of corrupting state

## Output layout

```
<domain>/
├── <domain>_history.csv                          per-run trend log
└── recon_YYYYMMDD/
    ├── log/recon_YYYYMMDD.log
    ├── tmp/                                       intermediate files
    └── report/
        ├── domains_found.txt                      all discovered subdomains
        ├── domains_diff.txt                       delta vs. previous run
        ├── domains_alive.txt                      subdomains that resolve
        ├── domains_without_resolution.txt         candidates for vhost probing
        ├── domains_excluded.txt
        ├── domains_aliases.txt
        ├── domains_thirdpart.txt
        ├── domains_infrastructure.txt
        ├── domains_internal_ipv4.txt
        ├── domains_external_ipv4.txt
        ├── domains_external_ipv6.txt
        ├── zone_transfer.txt
        ├── infra_as.txt
        ├── infra_ipv4.txt / infra_ipv4_diff.txt
        ├── infra_ipv6.txt / infra_blocks.txt
        ├── webapp_consolidated.txt                all live HTTP(S) URLs (DNS + validated vhosts)
        ├── webapp_consolidated_diff.txt
        ├── etc_hosts_file.txt                     vhost→IP map (ip<TAB>hostname format)
        ├── vhost_subdomains.txt                   STRONG vhost hits
        ├── vhost_subdomains_weak.txt              WEAK vhost hits
        ├── vhost_subdomains_diff.txt
        ├── email_recon.txt / email_recon_diff.txt
        ├── robots_urls.txt
        ├── webapp_js_secrets.txt                  hardcoded keys/tokens/JWTs in JS
        ├── webapp_js_params.txt                   param names + DOM sinks (SQLi/XSS/SSRF/...)
        ├── llm-local-prompt.txt                   LLM bundle: webapp_consolidated + etc_hosts
        ├── llm-claude-prompt.txt                  LLM bundle: all artifacts
        ├── scan/
        │   ├── nmap/nmap_scan.txt
        │   ├── nuclei/nuclei_scan.result
        │   ├── nuclei/nuclei_scan_diff.txt
        │   ├── nuclei/nuclei_web_fuzzing.result
        │   └── shodan/shodan_scan.txt
        └── webapp/
            ├── aquatone/                          screenshots
            ├── enum/                              gobuster + dirsearch output
            ├── javascript/                        downloaded JS files
            ├── params/                            katana + waybackurls output
            └── tech/                              response headers / fingerprinting
```

## Results database (SQLite)

After every run, `db_usage()` upserts the latest row into `${output_dir}/collector-results-db`. Schema: `targets(domain PK)` + `recon_runs(domain, run_id, ...)` with composite PK, `latest_run` view. Ingestion is idempotent — re-importing the same `run_id` only writes on payload change.

```bash
# Access from outside the container
sqlite3 /opt/collector/outputs/collector-results-db \
  "SELECT domain, run_date, findings_critical, findings_high, js_secrets FROM latest_run ORDER BY findings_critical DESC;"

sqlite3 /opt/collector/outputs/collector-results-db \
  "SELECT run_date, subdomains, webapp_consolidated, findings_critical FROM recon_runs WHERE domain='example.com' ORDER BY run_date DESC LIMIT 10;"
```

## Web UI

Flask + HTMX read-only dashboard auto-started at `http://127.0.0.1:8000` after each run. The port mapping is included by default in `docker-compose.yml` and `collector-docker`. With plain `docker run` add `-p 127.0.0.1:8000:8000` explicitly:

```bash
docker run --rm \
  -v /opt/collector/outputs:/app/outputs \
  -v /opt/collector/wordlists:/app/wordlists \
  -v /opt/collector/collector.cfg:/app/collector.cfg:ro \
  -p 127.0.0.1:8000:8000 \
  collector:latest \
  -d example.com --recon --webapp-discovery --webapp-short-detection

# docker compose and collector-docker already include -p 127.0.0.1:8000:8000
docker compose run --rm collector -d example.com --recon --webapp-discovery --webapp-short-detection
collector-docker -d example.com --recon --webapp-discovery --webapp-short-detection
```

Or set `cloudflare_tunnel="yes"` in `collector.cfg` for an ephemeral `https://*.trycloudflare.com` URL.

## Screenshots

![demo\_01.png](https://raw.githubusercontent.com/skateforever/collector/main/demo/demo_01.png)
![demo\_02.png](https://raw.githubusercontent.com/skateforever/collector/main/demo/demo_02.png)

## Thanks

[Alfredo Casanova](https://github.com/atcasanova) — bash code corrections.
[Caue Bici](https://github.com/caueobici) — code review and Python help.
[Enderson Maia](https://github.com/endersonmaia) — Dockerfile and shellcheck.
[Henrique Galdino](https://github.com/Achilles0x0) — curl options.
[Icaro Torres](https://github.com/icarot) — diff-based execution idea.
[Manoel Abreu](https://github.com/manoelt) — git-dumper integration idea.
[Rener aka gr1nch](https://github.com/renergr1nch/splitter) — splitter tool.
[Ulisses Alves](https://github.com/ualvesdias) — code review and Python help.

**Warning:** collector generates a substantial amount of traffic. Use only against targets you have explicit authorization to test.
