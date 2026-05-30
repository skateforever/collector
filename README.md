## collector

collector is a script written in Bash, it is intended to automate some tedious tasks of reconnaissance and information gathering. </br>
This tool allows you to gather some information that should help you identify what to do next and where to look. </br>

## System Requirements

Recommended to run on vps with 1VCPU and 2GB ram.

## To run

To run you need to install some tools and get some API keys. </br>

List of API/Web Sites for recon used in the collector:</br>

* alienvault
* builitwith
* certspotter
* commoncrawl
* crt.sh
* dnsdumpster
* hackertarget
* rapiddns
* securitytrails
* shodan
* virustotal
* webarchive
* whoisxmlapi

List of tools for recon used in the collector:</br>

* amass
* dnssearch
* gobuster
* subfinder
* tlsx
* wayback

List of tools for infrastructure scan used in the collector:</br>

* nmap

List of tools for webapp discovery:</br>

* aquatone
* chromium
* httpx

List of tools for webapp enumeration used in the collector:</br>

* dirsearch
* git-dumper
* gobuster

List of tools for webapp scan used in the collector:</br>

* nuclei

I tried my best to make the collector as simple as possible, but I also tried to ensure that the execution wasn't done haphazardly. Therefore, you'll notice that the execution is somewhat locked into a flow to obtain:

1. Domain, subdomains, IPs, and aliases;
2. Search for active web applications, but this depends on the first step; you need to execute the first step first;
3. Search for files, directories, and attempt to retrieve a Git repository, but this will only work if you complete step 2.

As you can see, I need to follow a logical sequence to obtain the expected result.</br>

## How collector works?

First step (passive + active subdomain discovery, infra, alive check):</br>
**./collector -d abc.com --recon --webapp-discovery**</br>

Second step (web enumeration over the URLs found in step 1):</br>
**./collector -d abc.com --webapp-enum --webapp-wordlist /path/to/wordlist**</br>

You can combine everything in a single run:</br>
**./collector -d abc.com --recon --webapp-discovery --webapp-enum --webapp-wordlist /path/to/wordlist --webapp-scan**</br>

Run against a list of targets (one domain per line, `#` for comments):</br>
**./collector -dl /etc/collector/targets.list --recon --webapp-discovery**</br>

Or enumerate a single URL only:</br>
**./collector --url http://abc.com --webapp-wordlist /path/to/wordlist**</br>

To see which ports are probed and tweak tool parameters, check **collector.cfg**. Use **./collector --help** for the full flag list.</br>

![collector-help.png](https://raw.githubusercontent.com/skateforever/collector/main/demo/collector-help.png) </br>

For unattended execution, drop-in `collector-cron` (cron) and `collector-systemd-timer` (systemd template units) are shipped at the repo root — daily light recon + weekly heavy run, with per-target locking so overlapping invocations abort cleanly.

**Use as you need.**

### Main features

- Per-run dated folder (`recon_YYYYMMDD`) with logs, tmp, and a structured report tree
- Subdomain discovery via amass, subfinder, certspotter, crt.sh, dnsdumpster, hackertarget, rapiddns, securitytrails, virustotal, webarchive, builtwith, whoisxmlapi, and others
- DNS bruteforce via amass, gobuster, dnssearch
- Infrastructure enrichment: AS / IPv4 / IPv6 / netblocks / nmap / shodan
- Per-artifact diff vs. the previous run (subdomains, IPs, webapp URLs, vhosts, emails, nuclei findings) — only deltas are pushed to the notify channel
- `_history.csv` per target: one row per execution with subdomain / IP / URL / vhost / email / finding counts (always written, even when there is no diff)
- Live-host detection over the ports listed in `webapp_port_detect`
- vhost discovery (parallel curl + httpx, STRONG vs. WEAK confidence)
- Email recon: Hunter.io, Lampyre, Snov.io, plus crawl of `webapp_urls.txt` (page root + referenced JS) filtered to the target domain
- Webapp enumeration with dirsearch and gobuster, plus `robots.txt` URL extraction
- JS scraping (katana) and parameter mining (waybackurls)
- Aquatone screenshots
- Nuclei scan
- Git repository rebuild via git-dumper
- Per-target lockfile (flock) so concurrent invocations for the same domain abort instead of corrupting state

### Output layout

A successful recon run produces the following tree under `${output_dir}/<domain>/recon_<date>/`:

```
<domain>/
├── _history.csv                                  per-run trend log (always appended)
├── domains_ignore.txt                            (optional, user-maintained allowlist)
└── recon_YYYYMMDD/
    ├── log/recon_YYYYMMDD.log
    ├── tmp/                                       intermediate files (json/tmp/html from each source)
    └── report/
        ├── domains_found.txt                      union of every subdomain source
        ├── domains_diff.txt                       added/removed vs. previous run
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
        ├── infra_as.txt                           AS / BGP prefix info from team-cymru
        ├── infra_ipv4.txt
        ├── infra_ipv4_diff.txt
        ├── infra_ipv6.txt
        ├── infra_blocks.txt                       owned netblocks
        ├── webapp_urls.txt                        live HTTP(S) URLs
        ├── webapp_urls_diff.txt
        ├── vhost_subdomains.txt                   STRONG hits (curl AND httpx differ from baseline)
        ├── vhost_subdomains_weak.txt              WEAK hits (only one probe differs)
        ├── vhost_subdomains_diff.txt
        ├── email_recon.txt
        ├── email_recon_diff.txt
        ├── webapp_js_secrets.txt                  hardcoded keys/tokens/JWTs found in downloaded JS
        ├── webapp_js_params.txt                   param names + DOM sinks worth manual review (SQLi/XSS/SSRF/XXE/CMD/...)
        ├── robots_urls.txt
        ├── scan/
        │   ├── nmap/nmap_scan.txt
        │   ├── nuclei/nuclei_scan.result
        │   ├── nuclei/nuclei_scan_diff.txt
        │   ├── nuclei/nuclei_web_fuzzing.result
        │   └── shodan/shodan_scan.txt
        └── webapp/
            ├── aquatone/                          screenshots + aquatone report
            ├── enum/<host>.gobuster.N             one file per (host, port)
            ├── enum/<host>.dirsearch.N
            ├── javascript/<host>/<file>.js        downloaded JS for offline review
            ├── params/                            katana / waybackurls output
            └── tech/<host>.tech                   response headers for fingerprinting
```

URL-only mode (`--url`) writes under `${output_dir}/<url_domain>/url_<date>/` with the same `report/` shape (no `nmap`/`shodan` since infra discovery is skipped).

### Screenshots

![demo\_01.png](https://raw.githubusercontent.com/skateforever/collector/main/demo/demo_01.png) </br>
![demo\_02.png](https://raw.githubusercontent.com/skateforever/collector/main/demo/demo_02.png) </br>

## Thanks

[Alfredo Casanova](https://github.com/atcasanova) with some bash code corrections. </br>
[Caue Bici](https://github.com/caueobici) with code review and answer some questions about python programming. </br>
[Enderson Maia](https://github.com/endersonmaia) with the help on Dockerfile and shellcheck tip. </br>
[Henrique Galdino](https://github.com/Achilles0x0) the help with some curl options. </br>
[Icaro Torres](https://github.com/icarot) with the ideia to diff files from a day ago to improve the execution time of the script. </br>
[Manoel Abreu](https://github.com/manoelt) with the ideia to use the [git-dumper.py](https://github.com/arthaud/git-dumper) in rebuild\_git function. </br>
[Rener aka gr1nch](https://github.com/renergr1nch/splitter) thanks to made the splitter, you rocks dude!! </br>
[Ulisses Alves](https://github.com/ualvesdias) with code review and answer some questions about python programming! </br>

## Resources

https://0xsp.com/offensive/red-teaming-toolkit-collection </br>
https://medium.com/@ricardoiramar/subdomain-enumeration-tools-evaluation-57d4ec02d69e </br>
https://github.com/riramar/Web-Attack-Cheat-Sheet </br>
https://inteltechniques.com/blog/2018/03/06/updated-osint-flowcharts/ </br>
https://github.com/sehno/Bug-bounty/blob/master/bugbounty_checklist.md </br>
https://github.com/renergr1nch/splitter </br>
https://bitbucket.org/splazit/docker-privoxy-alpine/src/master/ </br>
https://github.com/essandess/adblock2privoxy </br>
https://0xpatrik.com/subdomain-enumeration-2019/ </br>
https://blog.securitybreached.org/2017/11/25/guide-to-basic-recon-for-bugbounty/ </br>
https://medium.com/@shifacyclewala/the-complete-subdomain-enumeration-guide-b097796e0f3 </br>
https://www.secjuice.com/penetration-testing-for-beginners-part-1-an-overview/ </br>
https://www.secjuice.com/reconnaissance-for-beginners/ </br>
https://medium.com/@Asm0d3us/weaponizing-favicon-ico-for-bugbounties-osint-and-what-not-ace3c214e139 </br>
https://medium.com/hackernoon/10-rules-of-bug-bounty-65082473ab8c </br>
https://https://findomain.app/findomain-advanced-automated-and-modern-recon/ </br>
https://www.offensity.com/de/blog/just-another-recon-guide-pentesters-and-bug-bounty-hunters/ </br>
https://medium.com/hackcura/learning-path-for-bug-bounty-6173557662a7 </br>
https://eslam3kl.medium.com/simple-recon-methodology-920f5c5936d4 </br>
https://github.com/nahamsec/Resources-for-Beginner-Bug-Bounty-Hunters </br>
https://www.offensity.com/en/blog/just-another-recon-guide-pentesters-and-bug-bounty-hunters/ </br>
https://blog.projectdiscovery.io/reconnaissance-a-deep-dive-in-active-passive-reconnaissance/ </br>
https://0xffsec.com/handbook/information-gathering/subdomain-enumeration/#content-security-policy-csp-header </br>
https://www.ceeyu.io/resources/blog/subdomain-enumeration-tools-and-techniques </br>
https://securitytrails.com/blog/dns-enumeration </br>
https://securitytrails.com/blog/whois-records-infosec-industry </br>
https://thexssrat.medium.com/how-to-automate-your-broad-scope-recon-a4ff998dea0e </br>
https://github.com/JoshuaMart/ScopesExtractor </br>
https://blog.ethiack.com/blog/supercharging-bug-bounty-hunting-with-ai </br>
https://github.com/bhavesh-pardhi/Wordlist-Hub </br>
https://github.com/XploitPoy-777/All-In-One-DNS-Wordlist </br>
https://github.com/vavkamil/awesome-bugbounty-tools </br>
https://www.helviojunior.com.br/security/osint/localizando-ips-que-respondem-para-uma-url/ </br>

**Warning:** The code of all scripts find here was originally created for personal use, it generates a substantial amount of traffic, please use with caution. 
