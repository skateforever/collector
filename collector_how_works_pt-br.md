# Manual de utilização — collector

## 1. O que é o collector e qual o foco como ferramenta ofensiva

O `collector` é um script em Bash que automatiza a fase de reconhecimento (recon) e coleta de informações durante engajamentos de pentest e bug bounty. Ele roda **exclusivamente dentro de um container Docker**, o que isola dependências (Go, Python, Chromium, nmap, etc.) e garante que cada execução parta de um ambiente limpo e reprodutível.

O foco ofensivo é encadear, em um único pipeline, as etapas que normalmente um atacante executa manualmente no início de um teste contra um perímetro externo:

- enumeração passiva e ativa de subdomínios em ~30 fontes OSINT (crt.sh, securitytrails, shodan, virustotal, alienvault, commoncrawl, dnsdumpster, rapiddns, hackertarget, whoisxmlapi, etc.);
- enriquecimento da infraestrutura do alvo (ASN, blocos IPv4/IPv6, registros DNS, transferência de zona);
- varredura de portas com nmap e Shodan;
- descoberta de serviços HTTP(S) vivos com `httpx` e descoberta de vhosts (cabeçalho `Host` arbitrário) com classificação STRONG/WEAK e injeção automática em `/etc/hosts` do container;
- brute-force de diretórios e arquivos com `gobuster` + `dirsearch`, captura de `robots.txt`, `sitemap.xml`, screenshots com `aquatone`;
- crawling de JS com `katana` + `waybackurls`, mineração de parâmetros, classificação por sinks (SQLi/XSS/SSRF/XXE/CMD) e busca por segredos hardcoded (chaves de API, JWTs, tokens);
- coleta de e-mails do alvo via Hunter.io, IntelX, Lampyre, Snov.io e crawl do consolidado;
- detecção de subdomain takeover (`subjack`, `subzy` + fingerprints customizadas);
- scan de vulnerabilidades web com `nuclei`;
- diff por artefato entre runs (apenas deltas são empurrados para o canal de notificação);
- empacotamento de todos os artefatos em um único `llm-prompt.txt` pronto para análise por LLM;
- ingestão idempotente em SQLite e dashboard read-only em Flask + HTMX para consulta posterior.

Em outras palavras: o `collector` é o estágio de **descoberta de superfície de ataque** automatizado, projetado para entregar ao operador uma base sólida e organizada antes da fase de exploração.

## 2. Estrutura em árvore do repositório

```
collector/
├── Dockerfile                          symlink → Dockerfile-debian (imagem padrão)
├── Dockerfile-debian                   imagem oficial (python:3.12-slim + Go + Chromium)
├── Dockerfile-archlinux                imagem alternativa baseada em Arch
├── docker-compose.yml                  serviço pronto: volumes e -p já configurados
├── README.md                           documentação completa
├── TODO.md                             roadmap interno
│
├── collector                           script Bash principal (entrypoint do container)
├── collector-docker                    wrapper de host: injeta -v e -p e chama docker run
├── collector.cfg                       configuração: timeouts, threads, listas de portas, APIs
│
├── functions/                          módulos Bash carregados pelo collector
│   ├── utils.sh                        banner, reset_vars, redact_secrets
│   ├── check_binaries.sh               valida se todas as binárias necessárias existem no PATH
│   ├── check_execution.sh              valida flags + collector_acquire_lock (flock por target)
│   ├── check_structure.sh              cria a estrutura de diretórios do run (recon_YYYYMMDD/…)
│   ├── menu.sh                         parser de CLI e validação de domínios
│   ├── usage.sh                        tela de help
│   ├── message.sh                      mensagens start/finished/failed e integração com notify
│   ├── domains_sources.sh              orquestra a invocação de todos os módulos em sources/
│   ├── domains_recon.sh                pipeline principal para -d/-dl (recon + webapp + scan)
│   ├── url_recon.sh                    pipeline alternativo para -u (apenas webapp)
│   ├── files.sh                        joining/organizing subdomains + build_consolidated_urls (mescla de URLs, injeção em /etc/hosts)
│   ├── diff.sh                         calcula deltas por artefato vs. run anterior
│   ├── infra.sh                        ASN/IPv4/IPv6/netblocks + zone transfer
│   ├── emails_recon.sh                 harvesting de e-mails via APIs + crawl
│   ├── webapp_discovery.sh             httpx + lista de portas + webapp_consolidated.txt
│   ├── webapp_enum.sh                  gobuster + dirsearch + aquatone + robots/sitemap
│   ├── webapp_crawler.sh               katana + waybackurls + extração de JS e parâmetros
│   ├── git.sh                          git-dumper para repositórios .git expostos
│   ├── app_report.sh                   ciclo de vida do dashboard Flask/gunicorn (background + foreground via --report-only)
│   ├── cloudflare_tunnel.sh            quick-tunnel do cloudflared para o dashboard (opt-in)
│   ├── db_usage.sh                     ingestão SQLite idempotente do CSV de histórico por run
│   └── llm_prompt.sh                   build_llm_prompt + llm_emit_artifact (montador do bundle LLM)
│
├── scans/                              scanners chamados pelos pipelines de recon
│   ├── nmap.sh                         scan de portas
│   ├── shodan.sh                       enriquecimento via API Shodan
│   ├── nuclei.sh                       scan de vulnerabilidades web
│   ├── acunetix.sh                     integração opcional com Acunetix
│   ├── takeover.sh                     subjack + subzy + fingerprints customizadas
│   └── js_scans.sh                     scan_js_secrets + scan_js_params (scan estático baseado em regex)
│
├── sources/                            ~60 módulos OSINT — um arquivo por fonte/técnica
│   ├── alienvault.sh, crt.sh, certspotter.sh, securitytrails.sh, virustotal.sh,
│   ├── shodan.sh, censys.sh, fofa.sh, netlas.sh, leakix.sh, urlscan.sh,
│   ├── amass.sh, subfinder.sh, sublist3r.sh, tlsx.sh, waybackurls.sh, urlfinder.sh,
│   ├── katana.sh, spider.sh, robots-sitemap.sh,
│   ├── bruteforce.sh, ns-brute.sh, nsec-walk.sh, ptr-sweep.sh, asn-sweep.sh,
│   ├── caa-enum.sh, dns-mining.sh, srv-enum.sh, zonetransfer.sh,
│   ├── vhost-check.sh, vhost-probe.sh,
│   └── …  (cada arquivo expõe uma função, executada por domains_sources.sh)
│
├── support/
│   ├── runtime/                        ativos lidos em tempo de execução
│   │   ├── wordlists/                  vhost-probe-names.txt, user-agents.txt,
│   │   │                               takeover-fingerprints.txt
│   │   ├── patterns/                   regex de secrets e nomes de parâmetros sensíveis
│   │   ├── prompts/                    cabeçalho do llm-prompt.txt
│   │   └── schema/                     schema SQL do collector-results-db
│   └── templates/                      drop-ins para automação
│       ├── cron/collector              cron diário/semanal
│       ├── systemd/collector@          systemd timer template
│       └── notify/provider-config.yml  exemplo de config do projectdiscovery/notify
│
├── app-report/                         dashboard read-only (Flask + HTMX + gunicorn)
│   ├── app.py                          rotas, leitura do collector-results-db
│   ├── requirements.txt
│   └── templates/                      index, target, runs, findings, diff, artifact, raw
│
└── demo/                               screenshots de divulgação
```

## 3. Fluxo de funcionamento

O entrypoint do container é o script `collector`. Resumidamente o fluxo é:

1. **Bootstrap.** `collector` carrega `functions/utils.sh` (banner, helpers, reset de variáveis globais) e depois faz `source collector.cfg` para herdar timeouts, threads, listas de portas curta/longa e chaves de API.
2. **Carga de módulos.** Em sequência são feitos `source` em todos os arquivos de `functions/` essenciais (`menu.sh`, `usage.sh`, `check_*`, `domains_*`, `url_recon.sh`, `webapp_*`, `emails_recon.sh`, `git.sh`, `diff.sh`, `files.sh`, `infra.sh`, além dos módulos do dashboard `cloudflare_tunnel.sh`, `app_report.sh`, `db_usage.sh`, `llm_prompt.sh`) e em `scans/` (`acunetix.sh`, `nmap.sh`, `nuclei.sh`, `shodan.sh`, `js_scans.sh`).
3. **Validações.** `check_container` confirma que está rodando dentro do Docker (o script aborta fora dele); `check_binaries` valida a presença das ferramentas no PATH.
4. **Parse de CLI.** `menu "$@"` processa as flags (`-d`, `-dl`, `-u`, `-r`, `-wd`, `-we`, `-ws`, `-wc`, etc.). `validate_domain` aplica regex estrita a cada alvo. Sem argumentos, `usage` é exibido.
5. **Coerência.** `check_execution` valida combinações de flags inválidas, `check_parameter_conflicts` impede combinações mutuamente exclusivas, `check_directory_permission` testa se `/opt/collector/outputs` é gravável.
6. **Lock por alvo.** `collector_acquire_lock "${domain}"` usa `flock` para impedir execuções concorrentes contra o mesmo domínio (preserva a integridade dos `*_diff.txt`).
7. **Estrutura de diretórios.** `create_directory_structure` cria `outputs/<domain>/recon_YYYYMMDD/{log,tmp,report/{scan/{nmap,nuclei,shodan},webapp/{aquatone,enum,javascript,params,tech}}}`. Em modo "reuse" (rodando `-we`/`-ws`/`-wc` sem `-r`) ele reaproveita o recon_dir mais recente que tenha `domains_alive.txt`.
8. **Roteamento por modo de execução.** `domains_recon` (para `-d`/`-dl`) ou `url_recon` (para `-u`) decidem o subconjunto do pipeline a executar com base nas flags presentes. O fluxo "happy path" completo de `-d --recon --webapp-discovery --webapp-enum --webapp-crawler --webapp-scan` é:
   1. `subdomains_recon` — dispara em paralelo todas as fontes em `sources/` (APIs OSINT + bruteforce DNS opcional + amass/subfinder/tlsx);
   2. `joining_subdomains` — `files.sh` consolida todas as saídas brutas em `tmp/` num único `domains_found.txt`, deduplicado e filtrado pelo domínio raiz;
   3. `diff_domains` — gera `domains_diff.txt` (delta em relação ao último run);
   4. `organizing_subdomains` — separa em `domains_alive.txt` (resolvem DNS) vs. `domains_without_resolution.txt` (candidatos a vhost), gera `domains_aliases.txt`, `domains_thirdpart.txt`, `domains_excluded.txt`;
   5. `infra_data` — coleta ASN, blocos de IP, IPv4/IPv6 (internos vs. externos), tenta `zone transfer`;
   6. `nmap_scan` + `shodan_scan` — varredura de portas no conjunto de IPs externos;
   7. `webapp_alive` — `httpx` contra `domains_alive.txt` na lista de portas (curta com `-wsd` ou longa com `-wld`);
   8. `vhost_check` + `vhost_probe` — descobre vhosts servidos pelos IPs externos cujo nome não resolve em DNS, classifica em STRONG/WEAK, escreve `etc_hosts_file.txt` e adiciona ao `/etc/hosts` do container para que as demais ferramentas resolvam transparentemente;
   9. `build_consolidated_urls` — produz `webapp_consolidated.txt` (todas as URLs HTTP(S) vivas, DNS + vhosts STRONG);
   10. `webapp_tech` — captura cabeçalhos de resposta para fingerprinting (em `report/webapp/tech/`);
   11. `emails_recon` — Hunter.io + IntelX (phonebook target=2) + Lampyre + Snov.io + crawl de páginas/JS do consolidado;
   12. `crawler_js` + `crawler_params` — katana + waybackurls extraem JS, parâmetros e expandem `sitemap.xml` recursivamente; classifica parâmetros por sink e busca segredos hardcoded;
   13. `nuclei_scan` — scan de vulnerabilidades contra o consolidado;
   14. `webapp_enum` — gobuster + dirsearch contra o consolidado, `robots.txt`, `sitemap.xml`; `aquatone_screenshot` em cada lote; `git_rebuild` (git-dumper) se diretórios `.git/` forem encontrados;
   15. `diff_artifacts` — gera `*_diff.txt` para cada artefato relevante;
   16. `build_llm_prompt` — concatena todos os artefatos em `llm-prompt.txt` com cabeçalho de instruções;
   17. `record_history` — anexa uma linha ao `<domain>_history.csv` (CSV de tendência);
   18. `db_usage` — upsert idempotente da run no `collector-results-db` (SQLite, WAL, FKs);
   19. `start_app_report` — inicia (ou reaproveita) o gunicorn na porta 8000; opcionalmente sobe um tunnel Cloudflare se `cloudflare_tunnel="yes"`;
   20. `message "${domain}" finished` — envia notificação final via `notify` (Slack/Discord/Telegram/etc., conforme `provider-config.yaml`).

Para `-u <url>`, o pipeline é reduzido a webapp_enum + robots + sitemap + crawler + nuclei + aquatone — sem recon de subdomínios, infraestrutura ou nmap.

## 4. Arquivos esperados ao final e função de cada um

Todos os artefatos finais vivem em `outputs/<domain>/recon_YYYYMMDD/`:

`log/recon_YYYYMMDD.log` — log completo da execução (stderr + stdout das ferramentas), útil para debug e auditoria.

`tmp/` — saídas brutas intermediárias de cada fonte (JSON do crt.sh, HTML de dnsrepo, etc.). Pode ser inspecionado durante a execução com `tail`; é o material que `joining_subdomains` consolida.

### Subdomínios e DNS
`report/domains_found.txt` — todos os subdomínios descobertos, deduplicados e filtrados pelo domínio raiz.
`report/domains_diff.txt` — apenas o delta em relação ao último run (alimenta a notificação).
`report/domains_alive.txt` — subdomínios que resolvem em DNS; é a base para `webapp_alive`.
`report/domains_without_resolution.txt` — candidatos a vhost (não resolvem, mas aparecem em fontes).
`report/domains_excluded.txt` — itens filtrados via `-ed`/`-el`.
`report/domains_aliases.txt` — CNAMEs detectados (útil para takeover).
`report/domains_thirdpart.txt` — hosts apontando para infraestrutura de terceiros (CDN, SaaS).
`report/zone_transfer.txt` — resultado do AXFR (vazio se o servidor não permitir, o que é o esperado).

### Infraestrutura
`report/domains_infrastructure.txt` — visão consolidada da infra do alvo.
`report/domains_internal_ipv4.txt` / `domains_external_ipv4.txt` / `domains_external_ipv6.txt` — IPs separados por contexto (com mapeamento `hostname<TAB>ip`).
`report/infra_as.txt` — ASNs do alvo.
`report/infra_ipv4.txt` / `infra_ipv4_diff.txt` / `infra_ipv6.txt` / `infra_blocks.txt` — IPs e netblocks únicos detectados (com diff).

### Web
`report/webapp_consolidated.txt` — **o artefato central**: lista de todas as URLs HTTP(S) vivas (resolução DNS + vhosts STRONG validados). É o input de gobuster, dirsearch, nuclei, katana, aquatone.
`report/webapp_consolidated_diff.txt` — delta entre runs (foco do operador).
`report/etc_hosts_file.txt` — mapeamento `ip<TAB>hostname` injetado em `/etc/hosts` do container para que vhosts WEAK/STRONG sejam resolvidos por qualquer ferramenta.
`report/vhost_subdomains.txt` / `vhost_subdomains_weak.txt` / `vhost_subdomains_diff.txt` — hits de vhost classificados por confiança e seu delta.
`report/robots_urls.txt` — URLs extraídas dos `robots.txt` coletados.
`report/sitemap_urls.txt` — URLs colhidas recursivamente de `sitemap.xml`/`sitemapindex`.
`report/webapp_js_secrets.txt` — segredos, tokens, JWTs e chaves de API encontrados nos JS baixados.
`report/webapp_js_params.txt` — parâmetros descobertos + classificação por sink (SQLi, XSS, SSRF, XXE, CMD, etc.).

### E-mails
`report/email_recon.txt` / `email_recon_diff.txt` — endereços de e-mail do alvo (APIs + crawl), filtrados pelo domínio.

### Scans
`report/scan/nmap/nmap_scan.txt` — saída do nmap nos IPs externos.
`report/scan/shodan/shodan_scan.txt` — enriquecimento via API Shodan (portas, banners, CVEs).
`report/scan/nuclei/nuclei_scan.result` — findings do nuclei contra `webapp_consolidated.txt`.
`report/scan/nuclei/nuclei_scan_diff.txt` — delta dos findings entre runs.
`report/scan/nuclei/nuclei_web_fuzzing.result` — saída específica dos templates de fuzzing.

### Webapp enum
`report/webapp/aquatone/` — screenshots HTML+PNG de todas as URLs vivas (visão rápida da superfície).
`report/webapp/enum/` — saída bruta de gobuster e dirsearch por host.
`report/webapp/javascript/` — JS baixados (input para `webapp_js_secrets`/`webapp_js_params`).
`report/webapp/params/` — saída bruta de katana e waybackurls.
`report/webapp/tech/` — cabeçalhos de resposta para fingerprinting (Server, X-Powered-By, etc.).

### Síntese e persistência
`report/llm-prompt.txt` — bundle único com todos os artefatos acima e cabeçalho de instruções; pronto para colar em qualquer LLM e seguir com análise.
`<domain>_history.csv` (um nível acima, em `outputs/<domain>/`) — uma linha por run, alimenta tendência no dashboard.
`outputs/collector-results-db` — SQLite com `targets(domain PK)` + `recon_runs(domain, run_id, ...)` + view `latest_run`. Idempotente: re-rodar o mesmo `run_id` só grava se o payload mudou.

## 5. Comandos para executar o collector

Os exemplos abaixo usam o wrapper `collector-docker`, que injeta automaticamente os volumes (`outputs`, `wordlists`, `collector.cfg`) e o `-p 127.0.0.1:8000:8000`. Os mesmos comandos funcionam diretamente com `docker run --rm -v … collector:latest <flags>` ou `docker compose run --rm collector <flags>`.

### 5.1. Comandos básicos de reconhecimento

Recon "puro" — só descobre subdomínios, infra, ASN, IPs e roda nmap/Shodan. Não toca em HTTP:

```bash
collector-docker -d example.com --recon
```

O que entrega: `domains_found.txt`, `domains_alive.txt`, `domains_without_resolution.txt`, `infra_*.txt`, `scan/nmap/nmap_scan.txt`, `scan/shodan/shodan_scan.txt`, `email_recon.txt`. Bom como primeiro passo para mapear o perímetro sem gerar tráfego HTTP barulhento.

Recon + descoberta de aplicações web na lista curta de portas (definida em `collector.cfg` como `web_port_short_detection`):

```bash
collector-docker -d example.com --recon --webapp-discovery --webapp-short-detection
```

O que entrega: tudo do comando anterior + `webapp_consolidated.txt` (URLs HTTP(S) vivas), `vhost_subdomains.txt` (STRONG), `vhost_subdomains_weak.txt`, `etc_hosts_file.txt`, e `webapp/tech/` com cabeçalhos de fingerprinting. Este é o ponto de entrada típico para qualquer alvo novo.

### 5.2. Comandos intermediários

Enumeração de diretórios/arquivos contra um recon já feito (reuso do `recon_YYYYMMDD/` mais recente):

```bash
collector-docker -d example.com --webapp-enum \
  --webapp-wordlists /opt/collector/wordlists/common.txt
```

O que entrega: `webapp/enum/` (gobuster + dirsearch), `robots_urls.txt`, `sitemap_urls.txt`, `webapp/aquatone/` (screenshots), e se algum `.git/` for exposto, `git-dumper` reconstrói o repositório.

Crawler de JS e mineração de parâmetros (também reuso):

```bash
collector-docker -d example.com --webapp-crawler
```

O que entrega: `webapp/javascript/` (JS baixados), `webapp/params/` (saída de katana + waybackurls), `webapp_js_secrets.txt` (chaves/tokens/JWTs hardcoded) e `webapp_js_params.txt` (parâmetros com classificação por sink). Foco em achar vetores de injeção para a fase ofensiva.

Scan de vulnerabilidades isolado (também reuso):

```bash
collector-docker -d example.com --webapp-scan
```

O que entrega: `scan/nuclei/nuclei_scan.result` e `nuclei_scan_diff.txt` contra `webapp_consolidated.txt`.

Recon contra uma lista de alvos (cron/agenda em massa) com filtro de escopo:

```bash
collector-docker -dl /opt/collector/outputs/targets.list \
  --recon --webapp-discovery --webapp-short-detection \
  -el /opt/collector/outputs/exclude.list
```

O que entrega: o pipeline completo executado por alvo, com lock independente por domínio e cada alvo gerando seu próprio `outputs/<domain>/recon_YYYYMMDD/`.

URL única (sem recon de subdomínios, sem nmap/Shodan, sem vhost):

```bash
collector-docker -u https://app.example.com \
  --webapp-wordlists /opt/collector/wordlists/common.txt
```

O que entrega: pipeline de webapp completo (enum + robots + sitemap + crawler + nuclei + aquatone) contra apenas a URL informada. Ideal para escopos restritos a uma única aplicação.

### 5.3. Comando completo do collector

Pipeline end-to-end — recon + descoberta web + enumeração + crawler + scan de vulnerabilidades — em um único disparo:

```bash
collector-docker -d example.com \
  --recon \
  --webapp-discovery --webapp-short-detection \
  --webapp-enum --webapp-wordlists /opt/collector/wordlists/common.txt \
  --webapp-crawler \
  --webapp-scan
```

O que entrega: **todos** os artefatos descritos na seção 4, incluindo `llm-prompt.txt`, `<domain>_history.csv` atualizado, ingestão no `collector-results-db` e dashboard subindo em `http://127.0.0.1:8000`. Tipicamente é o comando agendado em cron/systemd (semanal) — o diff por artefato garante que apenas as mudanças vão para o canal de notificação.

### 5.4. Reabrir o dashboard sem rodar um novo recon

Ao final de cada recon, `start_app_report` sobe o dashboard Flask/gunicorn em background para que o operador tenha uma interface pronta para navegar nos resultados. Quando aquele container termina (ou o processo é derrubado), o dashboard vai junto — mas os dados continuam preservados no volume compartilhado `outputs/`. Para consultá-los de novo sem disparar outro scan, use `--report-only`:

```bash
collector-docker --report-only        # gunicorn em foreground em 127.0.0.1:8000, Ctrl-C encerra
collector-docker --report-stop        # encerra a partir de outro shell
```

`--report-only` exige um `collector-results-db` dentro de `outputs/` (aborta com mensagem clara caso contrário), recusa iniciar quando outra instância já estiver rodando (via pidfile + sondagem de porta no host) e é estritamente read-only — o Flask abre o SQLite com `mode=ro`. O wrapper nomeia esse container como `collector-report` (sobrescreva via `REPORT_CONTAINER_NAME=<nome>` no ambiente), que é o alvo de `--report-stop` no host.

Quando a porta host de `APP_PORT` (default `127.0.0.1:8000:8000`) já está ocupada — por exemplo porque um recon anterior deixou um dashboard em background rodando, ou outro container publica ali —, o `collector-docker` silenciosamente omite o `-p` do `docker run` em vez de abortar com "port already allocated". O recon continua e o dashboard já em execução renderiza os dados do novo run porque `outputs/` é compartilhado.

## 6. Mais detalhes

Para a referência completa de todas as flags, variáveis de ambiente do wrapper (`COLLECTOR_IMAGE`, `OUTPUTS_DIR`, `WORDLISTS_DIR`, `COLLECTOR_CFG`, `APP_PORT`, `NOTIFY_CONFIG`), parâmetros do `collector.cfg` (timeouts, threads, listas de portas, chaves de API, opções do Cloudflare quick-tunnel), templates de cron/systemd, integração com o `projectdiscovery/notify`, schema do banco SQLite e consultas prontas, **consulte o `README.md` do repositório do collector**.

> **Aviso:** o collector gera um volume significativo de tráfego. Use apenas contra alvos para os quais você tenha autorização explícita.
