FROM python:3.12-slim

# Configurações de Ambiente
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    DEBIAN_FRONTEND=noninteractive \
    GOROOT=/usr/local/go \
    GOPATH=/go \
    PATH="/usr/local/go/bin:/go/bin:${PATH}" \
    GOBIN=/usr/local/bin

WORKDIR /app

# 1. Dependências do Sistema
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc git curl wget unzip xz-utils make build-essential procps \
    libpcap-dev libssl-dev libffi-dev libcurl4-openssl-dev \
    jq dnsutils whois html2text chromium nmap sqlite3 \
    nano vim iputils-ping \
    && rm -rf /var/lib/apt/lists/*

# 2. Instalação do Go
RUN wget -q https://go.dev/dl/go1.26.2.linux-amd64.tar.gz -O /tmp/go.tar.gz && \
    tar -C /usr/local -xzf /tmp/go.tar.gz && \
    rm /tmp/go.tar.gz && \
    mkdir -p /go

# 3. Ferramentas Go
RUN go install github.com/projectdiscovery/tlsx/cmd/tlsx@latest && \
    go install github.com/projectdiscovery/notify/cmd/notify@latest && \
    go install github.com/projectdiscovery/urlfinder/cmd/urlfinder@latest && \
    go install github.com/tomnomnom/waybackurls@latest && \
    go install github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest && \
    go install github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest && \
    go install github.com/projectdiscovery/httpx/cmd/httpx@latest && \
    go install github.com/OJ/gobuster/v3@latest && \
    CGO_ENABLED=1 go install github.com/projectdiscovery/katana/cmd/katana@latest && \
    CGO_ENABLED=0 go install github.com/owasp-amass/amass/v5/cmd/amass@main && \
    go install github.com/evilsocket/dnssearch@master && \
    go install github.com/003random/getJS@latest

# 4. Ferramentas Python
RUN pip install --no-cache-dir --upgrade pip setuptools wheel && \
    pip install --no-cache-dir dirsearch git-dumper requests shodan sublist3r \
                                flask gunicorn

RUN wget -q https://raw.githubusercontent.com/christophetd/censys-subdomain-finder/master/censys-subdomain-finder.py -O /usr/local/bin/censys-subdomain-finder.py && \
    chmod +x /usr/local/bin/censys-subdomain-finder.py

# 5. Aquatone e MassDNS
RUN wget -q https://github.com/michenriksen/aquatone/releases/download/v1.7.0/aquatone_linux_amd64_1.7.0.zip -O /tmp/aquatone.zip && \
    unzip /tmp/aquatone.zip -d /usr/local/bin && \
    rm /tmp/aquatone.zip

RUN git clone --depth 1 https://github.com/blechschmidt/massdns.git /tmp/massdns && \
    cd /tmp/massdns && make && mv bin/massdns /usr/local/bin/ && rm -rf /tmp/massdns

# 6. Cloudflared (used by start_app_report when cloudflare_tunnel="yes" in
# collector.cfg). Quick-tunnel mode generates an ephemeral
# https://*.trycloudflare.com URL pointing at the local app-report port,
# so the dashboard can be reached without exposing the VPS IP/port.
RUN wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -O /usr/local/bin/cloudflared && \
    chmod +x /usr/local/bin/cloudflared

# 7. Configuração Final
COPY . .
RUN chmod +x collector && chmod +x functions/*.sh

# Fix output_dir to the mounted volume path so every run writes results
# to /app/outputs without requiring --output on every invocation.
RUN sed -i 's|^output_dir=.*|output_dir="/app/outputs"|' collector.cfg

# Expose the app-report (Flask/gunicorn) dashboard port.
EXPOSE 8000

# Volumes: outputs persists recon results across runs; wordlists holds the
# dirsearch/gobuster wordlists mounted from the host; cfg allows overriding
# collector.cfg (API keys, notify config, etc.) at runtime without rebuilding.
VOLUME ["/app/outputs", "/app/wordlists"]

# collector is the only entry point — parameters are passed directly:
#   docker run --rm -v $(pwd)/outputs:/app/outputs collector-image \
#       -d soluti.com.br --recon --webapp-discovery
ENTRYPOINT ["/app/collector"]