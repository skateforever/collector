# =============================================================================
# collector - GCP Terraform module
# =============================================================================
#
# Sobe uma VM no GCP que:
#   1. instala Docker + git
#   2. clona o repositorio collector em /opt/collector
#   3. monta um disco persistente em /opt/collector/outputs (sobrevive a
#      recriacao da VM - os resultados de recon nao sao perdidos)
#   4. builda a imagem `collector:latest`
#   5. instala os units systemd template de support/templates/systemd/
#      (collector@.service + collector@.timer)
#   6. opcionalmente habilita o timer para var.target_domain
#
# Acesso:
#   * SSH SOMENTE via IAP (35.235.240.0/20) - sem IP de SSH publico.
#       gcloud compute ssh collector --tunnel-through-iap --zone <zone>
#   * Dashboard Flask (porta 8000) tambem so via IAP TCP forwarding:
#       gcloud compute start-iap-tunnel collector 8000 \
#           --local-host-port=localhost:8000 --zone <zone>
#     ou ative `cloudflare_tunnel="yes"` em collector.cfg para uma URL
#     ephemera *.trycloudflare.com.
#
# collector.cfg e notify-provider.yaml (que carregam chaves/API keys) sao
# injetados via metadata da instancia (sensitive = true), nao via disco
# do Terraform e nao aparecem em texto-claro no plan/state textual.
#
# Pre-requisitos (no host onde voce roda terraform):
#   * conta GCP com billing ativo
#   * gcloud auth application-default login (ou GOOGLE_APPLICATION_CREDENTIALS)
#   * APIs habilitadas no projeto:
#       gcloud services enable compute.googleapis.com iap.googleapis.com \
#                                iamcredentials.googleapis.com
#
# Uso minimo:
#
#   cat > terraform.tfvars <<EOF
#   project_id    = "meu-projeto-gcp"
#   target_domain = "example.com"
#   EOF
#
#   terraform init
#   terraform apply
#
# Para passar o collector.cfg do repo (com suas API keys de Shodan, Hunter,
# IntelX, etc.) e o notify-provider.yaml (webhooks Discord/Slack/Telegram):
#
#   project_id          = "meu-projeto-gcp"
#   target_domain       = "example.com"
#   collector_cfg_path  = "../../../collector.cfg"
#   notify_config_path  = "../../../notify-provider.yaml"
#
# AVISO: collector gera trafego ofensivo (subdominio brute, nuclei, dirbust).
# Use SOMENTE contra alvos com autorizacao explicita. O endereco externo da
# VM e a origem de todo esse trafego.
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.40"
    }
  }
}

# -----------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------

variable "project_id" {
  description = "ID do projeto GCP onde a VM sera criada."
  type        = string
}

variable "region" {
  description = "Regiao GCP."
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "Zona GCP."
  type        = string
  default     = "us-central1-a"
}

variable "instance_name" {
  description = "Nome da VM."
  type        = string
  default     = "collector"
}

variable "machine_type" {
  description = "Tipo de maquina. collector usa chromium + ferramentas Go, entao mire em >= 4 vCPU / 16 GB."
  type        = string
  default     = "e2-standard-4"
}

variable "boot_disk_size_gb" {
  description = "Tamanho do disco de boot (Debian + Docker + imagem collector ~ 8 GB)."
  type        = number
  default     = 30
}

variable "outputs_disk_size_gb" {
  description = "Disco persistente montado em /opt/collector/outputs. Sobrevive a recriacao da VM."
  type        = number
  default     = 100
}

variable "outputs_disk_type" {
  description = "Tipo do disco de outputs (pd-standard | pd-balanced | pd-ssd)."
  type        = string
  default     = "pd-balanced"
}

variable "network" {
  description = "Rede VPC. Use 'default' para a rede padrao do projeto."
  type        = string
  default     = "default"
}

variable "subnetwork" {
  description = "Subrede. Deixe vazio para autoselecionar baseado em var.region."
  type        = string
  default     = ""
}

variable "collector_repo_url" {
  description = "URL git do repositorio collector. Pode ser HTTPS publico ou git@... com SSH key montada."
  type        = string
  default     = "https://github.com/skate4ever/collector.git"
}

variable "collector_repo_branch" {
  description = "Branch / tag / SHA a fazer checkout."
  type        = string
  default     = "main"
}

variable "target_domain" {
  description = "Dominio alvo. Se setado, o startup script habilita collector@<domain>.timer. Vazio = nao agendar."
  type        = string
  default     = ""
}

variable "on_calendar" {
  description = "Expressao OnCalendar do systemd timer. Default: todo dia 03:00 local."
  type        = string
  default     = "*-*-* 03:00:00"
}

variable "collector_cfg_path" {
  description = "Caminho LOCAL (no host onde voce roda terraform) do collector.cfg a ser embarcado na VM via metadata. Vazio = usar o collector.cfg que vem do proprio repo (sem API keys)."
  type        = string
  default     = ""
}

variable "notify_config_path" {
  description = "Caminho LOCAL do notify-provider.yaml (webhooks Discord/Slack/Telegram). Vazio = sem notificacoes."
  type        = string
  default     = ""
}

variable "iap_source_ranges" {
  description = "Faixas que podem chegar na VM via IAP. 35.235.240.0/20 e o range fixo do IAP TCP forwarding."
  type        = list(string)
  default     = ["35.235.240.0/20"]
}

variable "extra_ssh_source_ranges" {
  description = "Faixas EXTRA que podem fazer SSH direto (sem IAP). Deixe vazio para forcar IAP-only."
  type        = list(string)
  default     = []
}

variable "service_account_email" {
  description = "Email da SA a anexar na VM. Vazio = cria uma SA dedicada com permissoes minimas."
  type        = string
  default     = ""
}

variable "labels" {
  description = "Labels para todos os recursos."
  type        = map(string)
  default = {
    app     = "collector"
    purpose = "pentest-recon"
  }
}

variable "preemptible" {
  description = "Roda como spot/preemptible (mais barato, pode ser derrubada a qualquer momento). OK para recon agendado."
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Provider
# -----------------------------------------------------------------------------

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# -----------------------------------------------------------------------------
# Service account
# -----------------------------------------------------------------------------

resource "google_service_account" "collector" {
  count        = var.service_account_email == "" ? 1 : 0
  account_id   = "${var.instance_name}-sa"
  display_name = "collector recon VM"
  description  = "SA dedicada da VM collector. Sem roles - apenas identidade para IAP/logging."
}

# Roles minimos para escrita em Cloud Logging/Monitoring (ops agent default).
resource "google_project_iam_member" "collector_logs" {
  count   = var.service_account_email == "" ? 1 : 0
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.collector[0].email}"
}

resource "google_project_iam_member" "collector_metrics" {
  count   = var.service_account_email == "" ? 1 : 0
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.collector[0].email}"
}

locals {
  sa_email = var.service_account_email != "" ? var.service_account_email : google_service_account.collector[0].email
}

# -----------------------------------------------------------------------------
# Firewall
# -----------------------------------------------------------------------------
#
# Politica: nada de SSH publico. SSH so via IAP TCP forwarding
# (35.235.240.0/20). Dashboard Flask (8000) idem.

resource "google_compute_firewall" "collector_iap_ssh" {
  name          = "${var.instance_name}-allow-iap-ssh"
  network       = var.network
  direction     = "INGRESS"
  source_ranges = var.iap_source_ranges
  target_tags   = [var.instance_name]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  description = "SSH via IAP TCP forwarding (sem expor 22 publico)."
}

resource "google_compute_firewall" "collector_iap_dashboard" {
  name          = "${var.instance_name}-allow-iap-dashboard"
  network       = var.network
  direction     = "INGRESS"
  source_ranges = var.iap_source_ranges
  target_tags   = [var.instance_name]

  allow {
    protocol = "tcp"
    ports    = ["8000"]
  }

  description = "Acesso ao app-report Flask via IAP TCP forwarding."
}

# Regra opcional: SSH direto de IPs especificos (escritorio/VPN).
# So e criada se var.extra_ssh_source_ranges for nao-vazia.
resource "google_compute_firewall" "collector_direct_ssh" {
  count         = length(var.extra_ssh_source_ranges) > 0 ? 1 : 0
  name          = "${var.instance_name}-allow-direct-ssh"
  network       = var.network
  direction     = "INGRESS"
  source_ranges = var.extra_ssh_source_ranges
  target_tags   = [var.instance_name]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  description = "SSH direto de faixas explicitamente autorizadas."
}

# -----------------------------------------------------------------------------
# Persistent disk para /opt/collector/outputs
# -----------------------------------------------------------------------------

resource "google_compute_disk" "outputs" {
  name   = "${var.instance_name}-outputs"
  type   = var.outputs_disk_type
  size   = var.outputs_disk_size_gb
  zone   = var.zone
  labels = var.labels

  lifecycle {
    # Protege o disco contra delecao acidental do terraform destroy.
    # Para destruir de verdade, mude para false antes do destroy.
    prevent_destroy = true
  }
}

# -----------------------------------------------------------------------------
# Startup script
# -----------------------------------------------------------------------------
#
# Roda apos o primeiro boot. Idempotente: pode ser reexecutado.

locals {
  has_collector_cfg = var.collector_cfg_path != ""
  has_notify_cfg    = var.notify_config_path != ""

  collector_cfg_b64 = local.has_collector_cfg ? filebase64(var.collector_cfg_path) : ""
  notify_cfg_b64    = local.has_notify_cfg ? filebase64(var.notify_config_path) : ""

  startup_script = <<-EOT
    #!/usr/bin/env bash
    set -euo pipefail
    exec > >(tee -a /var/log/collector-startup.log) 2>&1
    echo "[collector-startup] $(date -u) - inicio"

    # ---- 1. Mount do disco persistente em /opt/collector/outputs ------------
    OUTPUTS_DEV="/dev/disk/by-id/google-${var.instance_name}-outputs"
    OUTPUTS_MNT="/opt/collector/outputs"
    mkdir -p "$OUTPUTS_MNT"

    # Aguarda o disco aparecer (anexa async).
    for i in $(seq 1 30); do
      [ -e "$OUTPUTS_DEV" ] && break
      sleep 2
    done

    if ! blkid "$OUTPUTS_DEV" >/dev/null 2>&1; then
      echo "[collector-startup] formatando $OUTPUTS_DEV como ext4"
      mkfs.ext4 -F -m 0 -E lazy_itable_init=0,lazy_journal_init=0,discard "$OUTPUTS_DEV"
    fi

    # fstab por UUID (sobrevive a rename de device).
    OUTPUTS_UUID="$(blkid -s UUID -o value "$OUTPUTS_DEV")"
    if ! grep -q "$OUTPUTS_UUID" /etc/fstab; then
      echo "UUID=$OUTPUTS_UUID  $OUTPUTS_MNT  ext4  defaults,nofail,discard  0  2" >> /etc/fstab
    fi
    mount -a
    chown -R 1000:1000 "$OUTPUTS_MNT" || true

    # ---- 2. Docker --------------------------------------------------------
    if ! command -v docker >/dev/null 2>&1; then
      apt-get update
      apt-get install -y --no-install-recommends ca-certificates curl gnupg git
      install -m 0755 -d /etc/apt/keyrings
      curl -fsSL https://download.docker.com/linux/debian/gpg \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
      chmod a+r /etc/apt/keyrings/docker.gpg
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
        > /etc/apt/sources.list.d/docker.list
      apt-get update
      apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      systemctl enable --now docker
    fi

    # Usuario dedicado pra rodar collector (matching com User=collector dos units).
    if ! id collector >/dev/null 2>&1; then
      useradd --system --create-home --shell /usr/sbin/nologin --groups docker collector
    else
      usermod -aG docker collector || true
    fi

    # ---- 3. Clone do repo --------------------------------------------------
    if [ ! -d /opt/collector/.git ]; then
      rm -rf /opt/collector
      git clone --branch "${var.collector_repo_branch}" --depth 1 \
        "${var.collector_repo_url}" /opt/collector
    else
      cd /opt/collector
      git fetch --depth 1 origin "${var.collector_repo_branch}" || true
      git checkout "${var.collector_repo_branch}" || true
      git reset --hard "origin/${var.collector_repo_branch}" || true
    fi

    # Garante que /opt/collector/outputs continua sendo o ponto de mount, mesmo
    # depois do git clone (que cria o dir vazio /opt/collector se nao existir).
    mount | grep -q " $OUTPUTS_MNT " || mount -a

    mkdir -p /opt/collector/wordlists

    # ---- 4. collector.cfg (opcional, via metadata) ------------------------
    META="http://metadata.google.internal/computeMetadata/v1/instance/attributes"
    if curl -sf -H "Metadata-Flavor: Google" "$META/collector-cfg-b64" -o /tmp/collector-cfg.b64; then
      base64 -d /tmp/collector-cfg.b64 > /opt/collector/collector.cfg
      chmod 0640 /opt/collector/collector.cfg
      chown root:docker /opt/collector/collector.cfg
      rm -f /tmp/collector-cfg.b64
      echo "[collector-startup] collector.cfg sobrescrito via metadata"
    fi

    # ---- 5. notify-provider.yaml (opcional, via metadata) -----------------
    mkdir -p /opt/collector
    if curl -sf -H "Metadata-Flavor: Google" "$META/notify-config-b64" -o /tmp/notify.b64; then
      base64 -d /tmp/notify.b64 > /opt/collector/notify-provider.yaml
      chmod 0640 /opt/collector/notify-provider.yaml
      chown root:docker /opt/collector/notify-provider.yaml
      rm -f /tmp/notify.b64
      echo "[collector-startup] notify-provider.yaml sobrescrito via metadata"
    else
      # collector.sh detecta a ausencia e simplesmente nao chama notify.
      : > /opt/collector/notify-provider.yaml.absent
    fi

    # ---- 6. Build da imagem -----------------------------------------------
    cd /opt/collector
    docker build -t collector:latest .

    # ---- 7. systemd units --------------------------------------------------
    # collector@.service + collector@.timer extraidos do template multi-block
    # em support/templates/systemd/collector@ - sao escritos abaixo com paths
    # ja resolvidos (sem o /etc/systemd/system/<name> separator do template).

    NOTIFY_MOUNT=""
    if [ -s /opt/collector/notify-provider.yaml ]; then
      NOTIFY_MOUNT="-v /opt/collector/notify-provider.yaml:/etc/collector/notify-provider.yaml:ro"
    fi

    cat > /etc/systemd/system/collector@.service <<SERVICE
    [Unit]
    Description=collector recon run for %i (Docker)
    Wants=network-online.target docker.service
    After=network-online.target docker.service

    [Service]
    Type=oneshot
    User=collector
    Group=docker
    ExecStart=/usr/bin/docker run --rm \\
        --name collector-%i \\
        -v /opt/collector/outputs:/opt/collector/outputs \\
        -v /opt/collector/wordlists:/opt/collector/wordlists \\
        -v /opt/collector/collector.cfg:/opt/collector/collector.cfg:ro \\
        $NOTIFY_MOUNT \\
        collector:latest \\
        -d %i --recon --webapp-discovery
    TimeoutStartSec=4h
    StandardOutput=journal
    StandardError=journal
    Restart=no

    [Install]
    WantedBy=multi-user.target
    SERVICE

    cat > /etc/systemd/system/collector@.timer <<TIMER
    [Unit]
    Description=collector recon timer for %i
    Requires=collector@%i.service

    [Timer]
    OnCalendar=${var.on_calendar}
    RandomizedDelaySec=30m
    Persistent=true
    Unit=collector@%i.service

    [Install]
    WantedBy=timers.target
    TIMER

    systemctl daemon-reload

    # ---- 8. Habilita o timer para o dominio alvo (se setado) --------------
    TARGET="${var.target_domain}"
    if [ -n "$TARGET" ]; then
      INSTANCE="$(systemd-escape "$TARGET")"
      systemctl enable --now "collector@$INSTANCE.timer"
      echo "[collector-startup] timer collector@$INSTANCE.timer habilitado (OnCalendar=${var.on_calendar})"
    else
      echo "[collector-startup] target_domain vazio - timer NAO habilitado. Habilite manualmente:"
      echo "  sudo systemctl enable --now collector@<dominio>.timer"
    fi

    echo "[collector-startup] $(date -u) - concluido"
  EOT
}

# -----------------------------------------------------------------------------
# Compute instance
# -----------------------------------------------------------------------------

resource "google_compute_instance" "collector" {
  name         = var.instance_name
  machine_type = var.machine_type
  zone         = var.zone
  tags         = [var.instance_name]
  labels       = var.labels

  boot_disk {
    initialize_params {
      image  = "debian-cloud/debian-12"
      size   = var.boot_disk_size_gb
      type   = "pd-balanced"
      labels = var.labels
    }
  }

  attached_disk {
    source      = google_compute_disk.outputs.id
    device_name = "${var.instance_name}-outputs"
    mode        = "READ_WRITE"
  }

  network_interface {
    network    = var.network
    subnetwork = var.subnetwork != "" ? var.subnetwork : null

    # collector PRECISA de IP externo para fazer recon (consultas a OSINT
    # APIs, DNS publico, varredura HTTP dos alvos). Sem ele a VM nao
    # consegue sair pra internet a menos que voce coloque um Cloud NAT.
    access_config {
      network_tier = "PREMIUM"
    }
  }

  service_account {
    email = local.sa_email
    scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring.write",
      "https://www.googleapis.com/auth/devstorage.read_only",
    ]
  }

  scheduling {
    preemptible                 = var.preemptible
    automatic_restart           = !var.preemptible
    provisioning_model          = var.preemptible ? "SPOT" : "STANDARD"
    instance_termination_action = var.preemptible ? "STOP" : null
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  metadata = merge(
    {
      # Bloqueia chaves SSH project-wide. Use OS Login ou metadata da
      # propria instancia.
      block-project-ssh-keys = "TRUE"
      enable-oslogin         = "TRUE"
      startup-script         = local.startup_script
    },
    local.has_collector_cfg ? { collector-cfg-b64 = local.collector_cfg_b64 } : {},
    local.has_notify_cfg ? { notify-config-b64 = local.notify_cfg_b64 } : {},
  )

  # Conteudo de metadata e considerado sensivel quando carrega
  # collector.cfg/notify-provider.yaml (API keys, webhooks).
  metadata_startup_script = null

  allow_stopping_for_update = true

  depends_on = [
    google_compute_firewall.collector_iap_ssh,
    google_compute_disk.outputs,
  ]
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "instance_name" {
  description = "Nome da VM criada."
  value       = google_compute_instance.collector.name
}

output "instance_zone" {
  description = "Zona da VM."
  value       = google_compute_instance.collector.zone
}

output "instance_external_ip" {
  description = "IP externo da VM (origem do trafego ofensivo)."
  value       = google_compute_instance.collector.network_interface[0].access_config[0].nat_ip
}

output "ssh_iap_command" {
  description = "Comando para SSH via IAP."
  value       = "gcloud compute ssh ${google_compute_instance.collector.name} --tunnel-through-iap --zone ${google_compute_instance.collector.zone} --project ${var.project_id}"
}

output "dashboard_iap_tunnel_command" {
  description = "Comando para abrir tunnel IAP no dashboard Flask (porta 8000)."
  value       = "gcloud compute start-iap-tunnel ${google_compute_instance.collector.name} 8000 --local-host-port=localhost:8000 --zone ${google_compute_instance.collector.zone} --project ${var.project_id}"
}

output "trigger_manual_run" {
  description = "Comando dentro da VM para disparar uma execucao manual (fora do schedule)."
  value       = var.target_domain != "" ? "sudo systemctl start collector@${var.target_domain}.service" : "sudo systemctl enable --now collector@<dominio>.timer  # target_domain nao foi setado no apply"
}
