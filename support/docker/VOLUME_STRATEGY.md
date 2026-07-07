# Docker Volume Strategy - Code Replication Without Image Rebuild

## Overview

The collector's Docker setup uses a **hybrid volume mount strategy** that replicates the **exact directory structure** from the host into the container **at runtime**, without requiring image rebuilds for code changes.

**Only binary/package changes** (Dockerfile modifications) require image rebuilds.

## How It Works

### 1. Script Detection (collector-docker)

When you run `collector-docker`, the wrapper script detects:

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "${SCRIPT_DIR}/collector.cfg" ]]; then
    DEFAULT_ROOT="${SCRIPT_DIR}"  # ← Using repo checkout directly
else
    DEFAULT_ROOT="/opt/collector"  # ← Using installed layout
fi
```

**Two Execution Paths:**

| Context | DEFAULT_ROOT | Use Case |
|---------|--------------|----------|
| `cd ~/Pentest/tools/collector && ./collector-docker` | `~/Pentest/tools/collector` | Development (this repo) |
| `/usr/local/bin/collector-docker` | `/opt/collector` | Production (installed) |

### 2. Volume Mount Strategy

For **every execution**, these volumes are mounted READ-ONLY from the host:

```bash
-v "${DEFAULT_ROOT}/collector:/opt/collector/collector:ro"
-v "${DEFAULT_ROOT}/functions:/opt/collector/functions:ro"
-v "${DEFAULT_ROOT}/scans:/opt/collector/scans:ro"
-v "${DEFAULT_ROOT}/sources:/opt/collector/sources:ro"
-v "${DEFAULT_ROOT}/support/runtime:/opt/collector/support/runtime:ro"
-v "${DEFAULT_ROOT}/support/templates/alerts:/opt/collector/support/templates/alerts:ro"
```

These are **WRITE-PROTECTED** (`:ro` flag), so container can't corrupt host files.

### 3. Result: 1:1 Structure Replication

```
HOST                                      CONTAINER
────────────────────────────────────────────────────────────
~/Pentest/tools/collector/                /opt/collector/
├── collector                          → collector (symlink to binary)
├── functions/                         → functions/ (live from host)
├── scans/                             → scans/ (live from host)
├── sources/                           → sources/ (live from host)
├── support/runtime/                   → support/runtime/ (live from host)
├── support/templates/alerts-notify/          → support/templates/alerts-notify/ (live from host)
├── collector.cfg                      → collector.cfg (live from host)
├── outputs/ (rw)                      → outputs/ (writable for results)
└── wordlists/ (rw)                    → wordlists/ (writable for data)
```

## Practical Impact

### Scenario 1: Code Change (Functions)

```bash
# On Host - Make a code change
$ vi functions/utils.sh
$ git add functions/utils.sh
$ git commit -m "fix: improve wait_with_timeout"

# Still Same Container Image!
$ collector-docker -d example.com --recon
# ✅ Code change is IMMEDIATELY available
# ✅ No Docker rebuild needed
# ✅ New fix is used by collector
```

**Why?** Functions are mounted as volumes from the host at runtime.

### Scenario 2: New Alert Provider

```bash
# On Host - Add new provider
$ cp support/templates/alerts-notify/slack-provider.yml ./slack-provider.yaml
$ # Edit with webhook URLs
$ vim slack-provider.yaml

# Update config
$ sed -i 's/discord-provider/slack-provider/' collector.cfg

# Still Same Container Image!
$ collector-docker -d example.com --recon
# ✅ New provider is IMMEDIATELY available
# ✅ No Docker rebuild needed
# ✅ collector uses Slack
```

**Why?** Alert templates are mounted as volumes from the host at runtime.

### Scenario 3: Binary/Package Update (Requires Rebuild)

```bash
# On Host - Update tool in Dockerfile
$ vim Dockerfile-debian
# Add: go install github.com/new-tool/tool@latest

# MUST rebuild image
$ docker build -f Dockerfile-debian -t collector:latest .

# Now run - will use updated binaries
$ collector-docker -d example.com --recon
# ✅ New binaries available
```

**Why?** Binaries are baked into the image at build-time, not mounted as volumes.

## Configuration at Runtime

### Using Current Directory

```bash
# Development - always uses code from current directory
$ cd ~/Pentest/tools/collector
$ ./collector-docker -d example.com --recon
# Uses: ~/Pentest/tools/collector/{functions,scans,sources,...}
```

### Using Installed Layout

```bash
# Production - uses code from installed location
$ /usr/local/bin/collector-docker -d example.com --recon
# Uses: /opt/collector/{functions,scans,sources,...}
```

### Override with Environment Variables

```bash
# Custom root directory
$ OUTPUTS_DIR=/data/outputs \
  WORDLISTS_DIR=/data/wordlists \
  collector-docker -d example.com --recon
# Uses: /data/outputs and /data/wordlists
```

## File Synchronization During Execution

### Files That Are LIVE (from host):

- ✅ `functions/*.sh` — Changes available immediately next execution
- ✅ `scans/*.sh` — Changes available immediately next execution
- ✅ `sources/*.sh` — Changes available immediately next execution
- ✅ `collector` — Main script, live from host
- ✅ `collector.cfg` — Read at startup, changes affect next execution
- ✅ `support/templates/alerts-notify/*` — Live from host
- ✅ `support/runtime/*` — Live from host

### Files That Are Baked (from image):

- 🐳 `/usr/local/go/` — Go toolchain (rebuild to update)
- 🐳 `/go/bin/` — Go binaries (rebuild to update)
- 🐳 `/usr/local/bin/` — System tools (rebuild to update)
- 🐳 Python packages — Installed at build-time (rebuild to update)

## Performance Implications

### Advantages

✅ **Instant code deployment** — No build time  
✅ **Easy debugging** — Edit, re-run, test  
✅ **Fast iteration** — Perfect for development  
✅ **Small images** — Only binaries, not source  

### Trade-offs

⚠️ **Mounts add ~5-10ms per container startup** (negligible)  
⚠️ **Requires host filesystem sync** (NFS, network mounts, etc.)  
⚠️ **Docker Desktop/Mac volume sync can be slow** (use native Linux for best performance)  

## Best Practices

### Development

```bash
# 1. Work from repo checkout
cd ~/Pentest/tools/collector

# 2. Make code changes
vi functions/utils.sh

# 3. Test immediately
./collector-docker -d example.com --recon

# 4. Commit when happy
git add functions/utils.sh
git commit -m "fix: ..."
```

### Production

```bash
# 1. Install binary
sudo install -m 0755 collector-docker /usr/local/bin/collector-docker

# 2. Setup directories
sudo mkdir -p /opt/collector/{outputs,wordlists}
sudo cp collector.cfg /opt/collector/collector.cfg

# 3. Update code from git
cd /opt/collector && git pull

# 4. Run (always uses current /opt/collector)
collector-docker -d example.com --recon
```

### CI/CD

```bash
# 1. Clone latest
git clone https://github.com/skateforever/collector.git
cd collector

# 2. Run (uses cloned code immediately)
./collector-docker -d example.com --recon --all-modules

# 3. Results persist in ./outputs
```

## Troubleshooting

### "My code changes aren't reflected!"

**Cause:** Running from different directory than where you edited.

**Solution:**
```bash
# Verify where you are
pwd

# Verify where collector-docker is looking
cd ~/Pentest/tools/collector
./collector-docker --help 2>&1 | head -3
```

### "Changes from git pull aren't used"

**Cause:** Running installed binary instead of repo version.

**Solution:**
```bash
# Check which collector-docker you're using
which collector-docker

# Either:
# 1. Use repo version explicitly
/full/path/to/repo/collector-docker -d example.com --recon

# 2. Or update /opt/collector and use installed version
cd /opt/collector && git pull
/usr/local/bin/collector-docker -d example.com --recon
```

### "Volume mount is slow"

**Cause:** Docker Desktop on Mac/Windows with network filesystem.

**Solution:**
- Use native Linux Docker for best performance
- Use `--userns=host` if on Linux with NFS
- Accept slight overhead for development convenience

## Summary

| Component | Source | Frequency | Rebuild Required |
|-----------|--------|-----------|------------------|
| Code (functions/, scans/, etc) | Host volumes | Every execution | ❌ No |
| Configuration (collector.cfg) | Host volumes | Every execution | ❌ No |
| Binaries (Go tools) | Image layer | At container startup | ✅ Yes (Dockerfile change) |
| System packages | Image layer | At container startup | ✅ Yes (Dockerfile change) |
| Alert templates | Host volumes | Every execution | ❌ No |
| Results (outputs/) | Host volumes | Persistent | — |

**TL;DR:** Code changes are immediate; only Dockerfile changes require rebuild.
