idx-vps-ollama
KVM & VPS automation to create VMs, manage remote VPS instances, and install Ollama as a checksum-verified systemd service.

This repository contains operational, production-minded tooling to:

create local KVM/cloud-image VMs (vm.sh),
manage remote VPS (vps.sh),
install Ollama (tools/ollama-install.sh) as a checksum-verified systemd service,
optionally run Ollama in Docker (docker-compose.yml),
develop reproducibly with Nix (dev.nix),
integrate via raw GitHub URLs for sandboxed runners (e.g., ixd.google.com) while pinning to tags/commits.
Table of contents

Project overview
Files in this repository
Quick start (pin to a commit/tag)
Ollama: choosing a release binary
Ollama: non-Docker systemd install (detailed + installer script)
Ollama: remote install using vps.sh (automated)
Ollama: Docker alternative (docker-compose)
Reverse proxy & TLS (Nginx & Caddy examples)
Model storage & management
Performance & sizing guidance
Pinning, SHA256 verification, and CI practice
Monitoring, logs & troubleshooting
Upgrade, rollback, and maintenance
Security checklist & systemd hardening
Integration with ixd.google.com (raw URL usage)
Contributing & license
Appendix: useful commands
Files in this repository

vm.sh — local VM manager (qemu + cloud-init).
vps.sh — remote VPS utilities (deploy, backup, snapshot, status, and remote Ollama install helper).
tools/ollama-install.sh — idempotent installer (non-Docker). Downloads a pinned Ollama binary, verifies SHA256, installs binary, creates a system account, creates data dir, writes systemd unit, enables & starts service, waits for health.
docker-compose.yml — optional Ollama container setup (example).
dev.nix — Nix dev-shell for reproducible dev environment.
.github/workflows/ci.yml — CI jobs (lint & smoke-check).
README.md, CONTRIBUTING.md, LICENSE
Quick start (pin to a commit or tag)
Important: always pin raw URLs to a tag or commit SHA. Do not use main or latest for production automation.

Install vm and vps scripts system-wide (replace placeholders):

bash
Copy
sudo curl -fsSL -o /usr/local/bin/vm \
  https://raw.githubusercontent.com/<OWNER>/<REPO>/<TAG>/vm.sh
sudo chmod +x /usr/local/bin/vm

sudo curl -fsSL -o /usr/local/bin/vps \
  https://raw.githubusercontent.com/<OWNER>/<REPO>/<TAG>/vps.sh
sudo chmod +x /usr/local/bin/vps

# Get a local copy of the Ollama installer (save in repo/tools or run from workstation)
curl -fsSL -o tools/ollama-install.sh \
  https://raw.githubusercontent.com/<OWNER>/<REPO>/<TAG>/tools/ollama-install.sh
chmod +x tools/ollama-install.sh
Ollama: choosing a release binary
Ollama release assets are published to GitHub Releases. Choose the correct asset for your platform/architecture (e.g., ollama-linux-amd64, ollama-linux-arm64, etc.).

DO:

Pin the asset URL to a release tag or commit.
Compute and record SHA256 on a secure host before deploying.
Compute SHA256 (examples)

Using nix:
Copy
nix-prefetch-url --type sha256 "https://github.com/ollama/ollama/releases/download/vX.Y.Z/ollama-linux-amd64"
Using curl + sha256sum:
Copy
curl -fsSL -o /tmp/ollama.bin "https://github.com/ollama/ollama/releases/download/vX.Y.Z/ollama-linux-amd64"
sha256sum /tmp/ollama.bin
Record both the exact URL and the SHA256 checksum; these two values are used to verify the binary on the remote server.

Ollama: non-Docker systemd install (recommended for VPS)
Overview

Installer: tools/ollama-install.sh (idempotent).
Expected invocation: sudo /path/to/tools/ollama-install.sh "<BINARY_URL>" ""
What it does:
downloads the binary (curl/wget),
verifies SHA256,
installs binary to /usr/local/bin/ollama,
creates a system user ollama and data dir /var/lib/ollama,
writes /etc/systemd/system/ollama.service with safe defaults,
enables & starts the service and waits for health check on http://127.0.0.1:11434/.
Suggested installer script (tools/ollama-install.sh)

Save the following file as tools/ollama-install.sh and make it executable. Inspect it before executing.
bash
Copy
How the installer works (summary)

uses curl to fetch the binary,
checks SHA256 and aborts on mismatch,
installs to /usr/local/bin/ollama,
creates a system user and /var/lib/ollama owned by that user,
writes systemd unit with safe restrictions (ProtectSystem, PrivateTmp, NoNewPrivileges),
starts & enables the service, then polls the local health endpoint.
Manual run on a VPS (recommended inspect-first method)

bash
Copy
# On your workstation, compute SHA256 and BINARY_URL first:
BINARY_URL="https://github.com/ollama/ollama/releases/download/vX.Y.Z/ollama-linux-amd64"
SHA256="$(nix-prefetch-url --type sha256 "$BINARY_URL")"
# OR:
curl -fsSL -o /tmp/ollama.bin "$BINARY_URL"
sha256sum /tmp/ollama.bin

# On the VPS (safe approach: fetch, inspect, then run):
ssh ubuntu@203.0.113.5
# On remote:
sudo curl -fsSL -o /tmp/ollama-install.sh "https://raw.githubusercontent.com/<OWNER>/<REPO>/<TAG>/tools/ollama-install.sh"
# Inspect file before running:
less /tmp/ollama-install.sh
# Run the installer with the pinned URL and SHA:
sudo bash /tmp/ollama-install.sh "$BINARY_URL" "$SHA256"
Verify:

Copy
sudo systemctl status ollama.service
sudo journalctl -u ollama.service -n 200 --no-pager
curl -fsS http://127.0.0.1:11434/
Ollama: remote install via vps.sh (automated)
vps.sh is a local helper that can upload tools/ollama-install.sh to a remote VPS and execute it with sudo. It is convenient for scripted remote installs (still inspect before running in production).

Usage:

bash
Copy
# Compute SHA256 locally
BINARY_URL="https://github.com/ollama/ollama/releases/download/vX.Y.Z/ollama-linux-amd64"
SHA256="$(nix-prefetch-url --type sha256 "$BINARY_URL")"

# Run remote installer (example)
./vps.sh ollama-install ubuntu@203.0.113.5 "$BINARY_URL" "$SHA256"

# Verify
./vps.sh status ubuntu@203.0.113.5
# or
ssh ubuntu@203.0.113.5 'curl -fsS http://127.0.0.1:11434/ || true; sudo systemctl status ollama.service'
Minimal vps.sh helper (example)

A minimal vps.sh that handles the single ollama-install task is included below. Save it as vps.sh and make it executable.
bash
Copy
Notes:

ssh may prompt for passwords if key-based auth is not set up.
Always inspect tools/ollama-install.sh before remote execution.
Extend vps.sh for other remote tasks (backup, snapshot, rollback) as needed.
Ollama: Docker alternative
If you prefer to run Ollama in Docker (isolation, easier rollback), include a pinned image and map a volume for data. Example docker-compose.yml:

yaml
Copy
version: "3.8"
services:
  ollama:
    image: ollama/ollama:vX.Y.Z   # pin to exact tag
    restart: unless-stopped
    ports:
      - "11434:11434"
    volumes:
      - ollama-data:/var/lib/ollama
    environment:
      - OLLAMA_PORT=11434

volumes:
  ollama-data:
    driver: local
Start:

Copy
docker-compose up -d
docker-compose logs -f ollama
curl -fsS http://127.0.0.1:11434/
Reverse proxy + TLS (recommended)
Do NOT expose the Ollama port (11434) to the public Internet directly. Put a TLS reverse proxy in front and add authentication.

Nginx example:

Copy
server {
    listen 443 ssl;
    server_name ollama.example.com;

    ssl_certificate /etc/letsencrypt/live/ollama.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/ollama.example.com/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:11434/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_buffering off;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }
}
Caddy example (automatic HTTPS):

Copy
ollama.example.com {
    reverse_proxy 127.0.0.1:11434
    # Add authentication plugins or middleware if required
}
Firewall:

Only allow ports 22 (SSH) and 443 (HTTPS). Close 11434 to the world (allow only localhost or reverse-proxy host).
Model management & storage considerations
Models live under Ollama data dir (default /var/lib/ollama).
Models may be tens to hundreds of GB. Use an SSD-backed partition with adequate capacity and IOPS.
Consider mounting a dedicated disk at /var/lib/ollama:
Use ext4 or xfs.
Use noatime (to reduce metadata writes) if acceptable.
Regularly snapshot / back up /var/lib/ollama if models should be preserved.
For multi-tenant setups, use a dedicated disk per tenant or storage with quotas.
Performance & sizing guidance (real-time LLMs)
Small CPU models: 8–16 GB RAM may run with high latencies.
Medium-size models: 32 GB RAM recommended for acceptable latency.
Large models or high throughput: 64 GB+ RAM or GPU instances are recommended.
Disk: NVMe/SSD recommended to reduce I/O stalls.
Swap: avoid relying on swap for performance-critical LLM inference; add RAM or use GPU.
CPU: high single-thread performance helps for CPU-only workloads.
Monitor memory, CPU, and queueing; use horizontal scaling or autoscaling when needed.
Pinning, SHA256 verification, and CI practices
Pin raw URLs to tags or commit SHAs; do not trust floating references.
Store the binary URL + SHA256 in your deployment config or release notes.
CI job suggestions:
Lint shell scripts (shellcheck).
Format scripts (shfmt).
A CI job that downloads the pinned Ollama asset and checks that the SHA256 matches the one recorded in repo config (does not execute the binary).
Example GitHub Actions job (check only):
yaml
Copy
name: verify-ollama-binary
on: [push, pull_request]
jobs:
  verify:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Check SHA256 of pinned Ollama binary
        run: |
          echo "Downloading pinned binary..."
          curl -fsSL -o /tmp/ollama.bin "https://github.com/ollama/ollama/releases/download/vX.Y.Z/ollama-linux-amd64"
          sha256sum /tmp/ollama.bin
          # Compare with canonical SHA stored in file or env
Monitoring, logs & troubleshooting
Useful commands:

Copy
# Service & logs
sudo systemctl status ollama.service
sudo journalctl -u ollama.service -f

# Health
curl -fsS http://127.0.0.1:11434/

# Disk usage
df -h /var/lib/ollama

# Memory/CPU
free -h
top / htop

# Check binary type
file /usr/local/bin/ollama
Common issues:

SHA mismatch: re-download and re-check the asset and URL.
Service failing: check journalctl -u ollama.service -n 200 and file permissions on /var/lib/ollama.
Port conflict: ensure 11434 is free, or change the systemd unit port and reverse proxy config.
Insufficient memory: Ollama may be killed by OOM; add RAM or run a smaller model.
Upgrade, rollback & maintenance
Upgrade:

Stop service: sudo systemctl stop ollama.service
Replace binary with new pinned binary (download + verify SHA).
sudo systemctl daemon-reload
sudo systemctl start ollama.service
Rollback:

Replace the binary with previously pinned binary and repeat the restart steps (test on staging first).
Maintenance tips:

Snapshot / backups of /var/lib/ollama.
Rotate logs with journald or external log aggregator.
Prune unused models if disk space is tight.
Security checklist & recommendations
Pin raw URLs and verify checksums.
Do not pipe remote scripts to shell. Download → inspect → run.
Use SSH keys and disable password auth in production.
Put Ollama behind an authenticated, TLS-enabled reverse proxy.
Restrict 11434 access via firewall (allow only localhost and reverse proxy).
Run Ollama as an unprivileged system account (ollama) and use systemd security options:
PrivateTmp=yes
ProtectSystem=full
NoNewPrivileges=yes
Limit capabilities
Use secrets managers for credentials; do not store plaintext secrets.
Monitor CPU, memory and disk, and configure alerts.
Integration with ixd.google.com (raw URL usage)
Pin raw URLs to a tag/commit.
Do not run uninspected scripts on production hosts.
Recommended flow in ixd:
Download pinned script into the runner workspace,
Display / audit script contents,
Run script inside an isolated container/VM on a test instance,
If test passes, run the installer on production VPS via the vps.sh path or controlled SSH.
Contributing
Fork and create a branch.
Format & lint:
Copy
shfmt -w -i 2 vm.sh vps.sh tools/ollama-install.sh
shellcheck -x vm.sh vps.sh tools/ollama-install.sh
Open a PR describing changes and test results.
License
MIT License — see LICENSE. Replace author/year for your own repo.

Appendix: useful commands & examples
Compute sha256 for an Ollama release:

bash
Copy
BINARY_URL="https://github.com/ollama/ollama/releases/download/vX.Y.Z/ollama-linux-amd64"
nix-prefetch-url --type sha256 "$BINARY_URL"
# or
curl -fsSL -o /tmp/ollama.bin "$BINARY_URL"
sha256sum /tmp/ollama.bin
Install Ollama remotely via vps.sh (once SHA computed):

bash
Copy
./vps.sh ollama-install ubuntu@<VPS_IP> "$BINARY_URL" "<SHA256>"
Check logs and service state remotely:

bash
Copy
ssh ubuntu@<VPS_IP> 'curl -fsS http://127.0.0.1:11434/ || true; sudo systemctl status ollama.service'
Repository & release creation example
bash
Copy
mkdir idx-vps-ollama
cd idx-vps-ollama
# add files: README.md (this file), vm.sh, vps.sh, tools/ollama-install.sh, dev.nix, docker-compose.yml, .github/workflows/ci.yml, CONTRIBUTING.md, LICENSE
git init
git add .
git commit -m "Initial commit: vm, vps, ollama installer, dev.nix, CI, README"
gh repo create <YOUR_GH_USER>/idx-vps-ollama --public --source=. --remote=origin --push
# Set repo metadata
gh repo edit <YOUR_GH_USER>/idx-vps-ollama --description "KVM & VPS automation to create VMs, deploy servers, and install Ollama (systemd)."
gh repo edit <YOUR_GH_USER>/idx-vps-ollama --add-topic vps kvm qemu cloud-init ollama nix scripts
git tag -a v1.0.0 -m "Initial release"
git push origin v1.0.0
