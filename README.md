## collector

collector is a Bash script that automates reconnaissance and information gathering during penetration tests and bug bounty hunting. It runs **exclusively inside a Docker container**.

## Quick start

Build the image once (or use `collector-update` for automated builds):

```bash
docker build -t collector:latest .
# or with collector-update script
./collector-update --build-only
```

Run a full recon + webapp discovery:

```bash
# docker run
docker run --rm \
  -v /opt/collector/outputs:/opt/collector/outputs \
  -v /opt/collector/wordlists:/opt/collector/wordlists \
  -v /opt/collector/collector.cfg:/opt/collector/collector.cfg:ro \
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

By default the compose file uses repo-relative paths, so a fresh clone works without `sudo` and without pre-creating directories:

| Mount source (host) | Mount target (container) |
|---|---|
| `./outputs` (auto-created on first run) | `/opt/collector/outputs` |
| `./wordlists` (auto-created on first run) | `/opt/collector/wordlists` |
| `./collector.cfg` (already in the repo) | `/opt/collector/collector.cfg` (read-only) |

To redirect any of these to a different host location, drop a `.env` file in the repo root (Docker Compose loads it automatically). Example:

```bash
# .env at the repo root
OUTPUTS_DIR=/data/recon/outputs
WORDLISTS_DIR=/data/wordlists
COLLECTOR_CFG=/etc/collector/collector.cfg
```

`.env` is git-ignored so your local layout never leaks to the repo.

> **Note:** `docker compose up` is **not** the right verb here. `collector` exits with the usage screen when called without arguments, which Compose would interpret as a service failure. Always use `docker compose run --rm collector <flags>`.

**`collector-docker`** — thin wrapper around `docker run` that injects volumes and the default port mapping automatically. **Scripts (`collector`, `functions/`, `scans/`, `sources/`, `support/runtime/`) are mounted as read-only volumes from the host**, meaning code changes are instantly available without rebuilding the Docker image. The image only needs rebuilding when binaries or system packages change.

The wrapper resolves its defaults with a hybrid strategy:

- Running from a repo checkout (i.e. `collector.cfg` sits next to the script), defaults point at that checkout — `git clone` and run without any sudo or filesystem prep.
- Installed to `/usr/local/bin/` (no `collector.cfg` next to the script), defaults fall back to `/opt/collector/`, the layout produced by `sudo install ...`.

Install it once and use it like a native command:

```bash
sudo install -m 0755 /opt/collector/collector-docker /usr/local/bin/collector-docker
sudo mkdir -p /opt/collector/{outputs,wordlists}
sudo cp /opt/collector/collector.cfg /opt/collector/collector.cfg
```

Override defaults via environment variables (`<root>` is the checkout directory or `/opt/collector`, per the rule above):

| Variable | Default |
|----------|---------|
| `COLLECTOR_IMAGE` | `collector:latest` |
| `OUTPUTS_DIR` | `<root>/outputs` |
| `WORDLISTS_DIR` | `<root>/wordlists` |
| `COLLECTOR_CFG` | `<root>/collector.cfg` |
| `APP_PORT` | `127.0.0.1:8000:8000` |
| `REPORT_CONTAINER_NAME` | `collector-report` |

When the host port in `APP_PORT` is already bound (by a previous recon container, an ongoing `--report-only` session, or any other listener), the wrapper silently drops the `-p` flag from `docker run` instead of failing with "port already allocated" — the recon still completes; if a sibling container's dashboard is publishing that port, its view mirrors this run's results (shared `outputs/` volume).

## Keeping collector up to date

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

## Command reference

### Target selection (required — pick one)

| Flag | Description |
|------|-------------|
| `-d \| --domain <domain>` | Single target domain. |
| `-dl \| --domain-list <file>` | File with one domain per line (`#` for comments). |
| `-u \| --url <url>` | Single URL — skips infra/subdomain recon, runs webapp enum only. |
| `-dr \| --dry-run` | Run all pre-flight validations (config, locks, structure) and print a summary without executing any recon. Useful to confirm setup before a long run. |

### Recon

| Flag | Description |
|------|-------------|
| `-r \| --recon` | Passive + active subdomain discovery, DNS, infra enrichment (AS/IPs/netblocks), nmap, Shodan. Entry point for any new target. |

### Webapp discovery and vhost validation (requires `--recon` or existing `domains_alive.txt`)

| Flag | Description |
|------|-------------|
| `-wd \| --webapp-discovery` | Probes live hosts for active HTTP(S) services and builds `webapp_consolidated.txt`. Vhost discovery is **not** included unless `-vv` is also passed. |
| `-vv \| --vhost-validation` | Runs `vhost_check` and `vhost_probe` against live IPs to discover virtual hosts (STRONG/WEAK classification). Requires `-wd`. Without this flag, vhost checks are skipped entirely. |
| `-wsd \| --webapp-short-detection` | Uses the short port list from `collector.cfg` (`web_port_short_detection`). Use with `-wd`. |
| `-wld \| --webapp-long-detection` | Uses the long port list from `collector.cfg` (`web_port_long_detection`). Use with `-wd`. |

### Webapp enumeration (requires existing `webapp_consolidated.txt` or combined with `--webapp-discovery`)

| Flag | Description |
|------|-------------|
| `-we \| --webapp-enum` | Directory and file brute-force with gobuster + dirsearch, robots.txt extraction, aquatone screenshots. |
| `-ww \| --webapp-wordlists <file[,file]>` | Extra wordlists for `-we`. |
| `-l \| --limit-urls <n>` | Limit enumeration to the top N URLs (used with `-d`). |

> **Wordlist paths are resolved inside the container.** `-ww` and `-s|--subdomain-brute` both pass paths straight through to a bash `[[ -s ... ]]` test that runs *inside* the container, so a host path like `~/my.txt` or `/home/leandro/lists/big.txt` won't work by itself. Stage the file under `${WORDLISTS_DIR}` on the host (default: `<root>/wordlists`, mounted at `/opt/collector/wordlists`) and pass the container path — e.g. `--webapp-wordlists /opt/collector/wordlists/big.txt`. Alternatively, override `WORDLISTS_DIR=<dir-that-contains-your-file>` when invoking `collector-docker` so the wrapper mounts that dir instead.

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

### Dashboard control

The app-report dashboard is started automatically at the end of each recon (in the background). These flags let you reopen or stop it without triggering another recon.

| Flag | Description |
|------|-------------|
| `-ro \| --report-only` | Open the read-only app-report dashboard against the existing `outputs/` directory and stay in the foreground. Skips recon entirely; requires a `collector-results-db` from a previous run. Ctrl-C or `--report-stop` (from another shell) stops it. |
| `-rs \| --report-stop` | Stop a dashboard previously started with `--report-only`. Sends SIGTERM, waits 5 s, then SIGKILLs if needed. Via `collector-docker` it does the equivalent `docker stop collector-report` on the host. |

> **On stopping recon runs:** collector runs in a one-shot container, so the right way to abort an in-flight recon is `docker stop <container>` on the host. To wipe artifacts, `rm -rf` the target's directory under `outputs/`. Per-target `flock` already prevents concurrent runs against the same domain.

## Common usage patterns

Full recon + webapp discovery (short port list, no vhost):

```bash
docker run --rm \
  -v /opt/collector/outputs:/opt/collector/outputs \
  -v /opt/collector/wordlists:/opt/collector/wordlists \
  -v /opt/collector/collector.cfg:/opt/collector/collector.cfg:ro \
  collector:latest \
  -d example.com --recon --webapp-discovery --webapp-short-detection

docker compose run --rm collector \
  -d example.com --recon --webapp-discovery --webapp-short-detection

collector-docker -d example.com --recon --webapp-discovery --webapp-short-detection
```

Full recon + webapp discovery + vhost validation (short port list):

```bash
collector-docker -d example.com --recon --webapp-discovery --webapp-short-detection --vhost-validation
```

Full recon + webapp discovery + enum + scan in one shot (with vhost):

```bash
docker run --rm \
  -v /opt/collector/outputs:/opt/collector/outputs \
  -v /opt/collector/wordlists:/opt/collector/wordlists \
  -v /opt/collector/collector.cfg:/opt/collector/collector.cfg:ro \
  collector:latest \
  -d example.com --recon --webapp-discovery --webapp-short-detection --vhost-validation \
  --webapp-enum --webapp-wordlists /opt/collector/wordlists/common.txt --webapp-scan

docker compose run --rm collector \
  -d example.com --recon --webapp-discovery --webapp-short-detection --vhost-validation \
  --webapp-enum --webapp-wordlists /opt/collector/wordlists/common.txt --webapp-scan

collector-docker -d example.com --recon --webapp-discovery --webapp-short-detection \
  --webapp-enum --webapp-wordlists /opt/collector/wordlists/common.txt --webapp-scan
```

Standalone webapp enum on a previously recon'd target:

```bash
docker run --rm \
  -v /opt/collector/outputs:/opt/collector/outputs \
  -v /opt/collector/wordlists:/opt/collector/wordlists \
  -v /opt/collector/collector.cfg:/opt/collector/collector.cfg:ro \
  collector:latest \
  -d example.com --webapp-enum --webapp-wordlists /opt/collector/wordlists/common.txt

docker compose run --rm collector \
  -d example.com --webapp-enum --webapp-wordlists /opt/collector/wordlists/common.txt

collector-docker -d example.com --webapp-enum --webapp-wordlists /opt/collector/wordlists/common.txt
```

Standalone webapp scan on a previously recon'd target:

```bash
docker run --rm \
  -v /opt/collector/outputs:/opt/collector/outputs \
  -v /opt/collector/wordlists:/opt/collector/wordlists \
  -v /opt/collector/collector.cfg:/opt/collector/collector.cfg:ro \
  collector:latest \
  -d example.com --webapp-scan

docker compose run --rm collector -d example.com --webapp-scan

collector-docker -d example.com --webapp-scan
```

Standalone JS crawler:

```bash
docker run --rm \
  -v /opt/collector/outputs:/opt/collector/outputs \
  -v /opt/collector/wordlists:/opt/collector/wordlists \
  -v /opt/collector/collector.cfg:/opt/collector/collector.cfg:ro \
  collector:latest \
  -d example.com --webapp-crawler

docker compose run --rm collector -d example.com --webapp-crawler

collector-docker -d example.com --webapp-crawler
```

List of targets:

```bash
docker run --rm \
  -v /opt/collector/outputs:/opt/collector/outputs \
  -v /opt/collector/wordlists:/opt/collector/wordlists \
  -v /opt/collector/collector.cfg:/opt/collector/collector.cfg:ro \
  collector:latest \
  -dl /opt/collector/outputs/targets.list --recon --webapp-discovery --webapp-short-detection

docker compose run --rm collector \
  -dl /opt/collector/outputs/targets.list --recon --webapp-discovery --webapp-short-detection

collector-docker -dl /opt/collector/outputs/targets.list --recon --webapp-discovery --webapp-short-detection
```

Single URL (no subdomain/infra discovery):

```bash
docker run --rm \
  -v /opt/collector/outputs:/opt/collector/outputs \
  -v /opt/collector/wordlists:/opt/collector/wordlists \
  -v /opt/collector/collector.cfg:/opt/collector/collector.cfg:ro \
  collector:latest \
  -u https://opt/collector.example.com --webapp-wordlists /opt/collector/wordlists/common.txt

docker compose run --rm collector \
  -u https://opt/collector.example.com --webapp-wordlists /opt/collector/wordlists/common.txt

collector-docker -u https://opt/collector.example.com --webapp-wordlists /opt/collector/wordlists/common.txt
```

Pre-flight check (dry run) — validates config and parameters without running anything:

```bash
collector-docker -d example.com --recon --webapp-discovery --webapp-short-detection --dry-run
```

## Unattended execution

Drop-in scheduling files are in `support/templates/`:

- `support/templates/cron/collector` — daily light recon + weekly heavy run via cron (`/etc/cron.d/collector`)
- `support/templates/systemd/collector@` — same cadence as systemd template units (`collector@<domain>.timer`)
- `support/templates/alerts/` — alert provider templates for [notify](https://github.com/projectdiscovery/notify): Discord, Slack, Teams, Telegram, Signal. Templates are baked into the Docker image at `/opt/collector/support/templates/alerts/`. To use a custom provider config (e.g., with real webhook URLs), copy your config outside the repo and bind-mount via `ALERT_PROVIDER` in your `.env`. See `support/templates/alerts/README.md` for setup guides and examples.

Both use `collector-docker` (or `docker run --rm` directly) — each run fires an ephemeral container. Results persist via the `/opt/collector/outputs` volume. Per-target `flock` prevents overlapping runs for the same domain when triggered by cron or timers.

## APIs and tools used

**Subdomain sources:** alienvault, builtwith, certspotter, commoncrawl, crt.sh, dnsdumpster, hackertarget, rapiddns, securitytrails, shodan, virustotal, webarchive, whoisxmlapi

**Recon tools:** amass, dnssearch, gobuster, subfinder, tlsx, waybackurls

**Infrastructure:** nmap, shodan

**Webapp discovery:** httpx, chromium

**Webapp enumeration:** dirsearch, ffuf, gobuster, git-dumper

**Webapp crawler:** katana, waybackurls (sitemap.xml expansion built in)

**Webapp scan:** nuclei

**Screenshots:** aquatone

**Email recon:** Hunter.io, IntelX (phonebook target=2), Lampyre, Snov.io (API-based) + page/JS crawl of `webapp_consolidated.txt`

**Reporting:** sqlite3, Flask, gunicorn, HTMX

## Main features

- Per-run dated folder (`recon_YYYYMMDD`) with logs, tmp, and structured report tree
- Subdomain discovery via passive sources + active DNS bruteforce
- Infrastructure enrichment: AS / IPv4 / IPv6 / netblocks / nmap / Shodan
- vhost discovery (opt-in via `-vv`): parallel curl + httpx probing, STRONG vs. WEAK confidence classification, automatic `/etc/hosts` injection inside the container so all tools resolve vhosts transparently. Optional `ffuf`-backed mode for orders-of-magnitude faster probing (set `vhost_use_ffuf=yes` in `collector.cfg`)
- `-dr|--dry-run` pre-flight validation mode — confirm config and parameters before a long run
- Per-artifact diff vs. previous run — only deltas pushed to notify channel
- Email harvesting from APIs + page/JS crawl filtered to the target domain
- JS scraping and parameter mining with sink classification (SQLi/XSS/SSRF/XXE/CMD/...)
- Single LLM prompt bundle per run: `llm-prompt.txt` — all artifacts included, ready to paste into any LLM for follow-up analysis
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
        ├── sitemap_urls.txt                       URLs harvested from sitemap.xml (recursive sitemapindex)
        ├── webapp_js_secrets.txt                  hardcoded keys/tokens/JWTs in JS
        ├── webapp_js_params.txt                   param names + DOM sinks (SQLi/XSS/SSRF/...)
        ├── llm-prompt.txt                         LLM bundle: all artifacts
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
  -v /opt/collector/outputs:/opt/collector/outputs \
  -v /opt/collector/wordlists:/opt/collector/wordlists \
  -v /opt/collector/collector.cfg:/opt/collector/collector.cfg:ro \
  -p 127.0.0.1:8000:8000 \
  collector:latest \
  -d example.com --recon --webapp-discovery --webapp-short-detection

# docker compose and collector-docker already include -p 127.0.0.1:8000:8000
docker compose run --rm collector -d example.com --recon --webapp-discovery --webapp-short-detection
collector-docker -d example.com --recon --webapp-discovery --webapp-short-detection
```

Reopening the dashboard from an earlier scan (no new recon):

```bash
collector-docker --report-only         # foreground, Ctrl-C to stop
collector-docker --report-stop         # stop from another shell
```

`--report-only` names its container `collector-report` (override with `REPORT_CONTAINER_NAME=<name>`) and refuses to start when one is already running. It requires `collector-results-db` to exist in the `outputs/` directory — otherwise it aborts with a clear message rather than serving an empty dashboard.

Or set `cloudflare_tunnel="yes"` in `collector.cfg` for an ephemeral `https://*.trycloudflare.com` URL (only meaningful when the dashboard runs in the background, i.e. at end-of-recon; `--report-only` doesn't publish a tunnel).

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
