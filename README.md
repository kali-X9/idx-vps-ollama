# idx-vps-ollama

KVM & VPS automation to create VMs, deploy servers, and install Ollama (systemd).  
This repository contains operational, production-minded tooling to:
- create local KVM/cloud-image VMs (vm.sh),
- manage remote VPS (vps.sh),
- install Ollama (tools/ollama-install.sh) as a checksum-verified systemd service,
- optionally run Ollama in Docker (docker-compose.yml),
- develop reproducibly with Nix (dev.nix),
- integrate via raw GitHub URLs for platforms like ixd.google.com.

This README is intentionally comprehensive — it includes step-by-step Ollama setup instructions (non-Docker & Docker), reverse-proxy/TLS configurations, remote installer workflow, best practices for pinning/verifying releases, performance sizing, monitoring, upgrade/rollback, and security hardening.

Table of contents
- Project overview
- Files in this repository
- Quick start (raw GitHub)
- Ollama: prerequisites & how to pick a binary
- Ollama: non-Docker systemd install (detailed)
- Ollama: remote install via vps.sh (automated)
- Ollama: Docker alternative (docker-compose)
- Ollama: reverse proxy + TLS (Nginx & Caddy examples)
- Model management & storage considerations
- Performance & sizing guidance for real-time usage
- Pinning, SHA256 verification, and CI practices
- Monitoring, logs, and troubleshooting
- Upgrade, rollback, and maintenance
- Security checklist and recommendations
- Integration with ixd.google.com (raw URL usage)
- Contributing & license
- Appendix: useful commands

Files in this repository
- `vm.sh` — local VM manager (qemu + cloud-init).
- `vps.sh` — remote VPS utilities (deploy, backup, snapshot, status, remote ollama install).
- `tools/ollama-install.sh` — idempotent installer (non-Docker) that installs a pinned Ollama binary, creates a systemd service, and verifies SHA256.
- `docker-compose.yml` — optional Ollama container config.
- `dev.nix` — Nix dev-shell exposing vm & vps commands.
- `.github/workflows/ci.yml` — lint and smoke-check CI.
- `README.md`, `CONTRIBUTING.md`, `LICENSE`.

Quick start (pin to a commit or tag)
-----------------------------------
Always reference a specific commit SHA or tag in raw URLs (do not use `main` for production).

System-wide install examples (replace placeholders):
```bash
# Install vm and vps scripts (pin to tag/commit)
sudo curl -fsSL -o /usr/local/bin/vm \
  https://raw.githubusercontent.com/<OWNER>/<REPO>/<TAG>/vm.sh
sudo chmod +x /usr/local/bin/vm

sudo curl -fsSL -o /usr/local/bin/vps \
  https://raw.githubusercontent.com/<OWNER>/<REPO>/<TAG>/vps.sh
sudo chmod +x /usr/local/bin/vps

# Download ollama installer script (local copy)
curl -fsSL -o tools/ollama-install.sh \
  https://raw.githubusercontent.com/<OWNER>/<REPO>/<TAG>/tools/ollama-install.sh
chmod +x tools/ollama-install.sh

Copilot said: Got it — this README is ready
Got it — this README is ready to use. I pasted it below as a ready-to-commit README.md file and included the exact next steps to create the GitHub repo, add the other files (vm.sh, vps.sh, tools/ollama-install.sh, dev.nix, docker-compose.yml, CI), pin a release, and compute the Ollama binary SHA256 you must provide before installing to any VPS.

Save this file as README.md at the repo root (name and content are included). After the file block I provide the recommended next commands to create/push the repository and to compute/pin the Ollama binary SHA256.

README.md
v6
# idx-vps-ollama

KVM & VPS automation to create VMs, deploy servers, and install Ollama (systemd).  
This repository contains operational, production-minded tooling to:
- create local KVM/cloud-image VMs (vm.sh),
- manage remote VPS (vps.sh),
Ollama: prerequisites & choosing a binary Before installing Ollama (non-Docker), choose a release binary for your VPS architecture (e.g., linux-amd64). Ollama releases are hosted on GitHub Releases.

Select the correct binary URL for your OS/arch from the Ollama releases page.
Do NOT use ambiguous latest links in production — pin the exact release tag or commit.
Compute & verify SHA256:
Locally:
bash
curl -fsSL -o /tmp/ollama.bin "<BINARY_URL>"
sha256sum /tmp/ollama.bin
Or use Nix helper:
bash
nix-prefetch-url --type sha256 "<BINARY_URL>"
Record the exact URL and SHA256 in your release notes or deployment configuration.
Ollama: non-Docker systemd install (recommended for VPS) This is the recommended approach when you want a native, systemd-managed Ollama server on a VPS (no container).

A. Installer script (already in this repo)

tools/ollama-install.sh is idempotent and expects:
argument 1: BINARY_URL
argument 2: SHA256
B. How the installer works (summary)

Downloads the binary (curl or wget).
Verifies SHA256 — aborts on mismatch.
Installs binary to /usr/local/bin/ollama.
Creates a system user ollama and a data directory /var/lib/ollama.
Writes /etc/systemd/system/ollama.service:
ExecStart: /usr/local/bin/ollama server --port 11434 --data-dir /var/lib/ollama
Enables and starts the service, waiting for health endpoint http://127.0.0.1:11434/.
C. Run the installer locally on a VPS (manual)

Transfer the installer or curl it on the VPS:
bash
# On VPS
sudo curl -fsSL -o /tmp/ollama-install.sh \
  https://raw.githubusercontent.com/<OWNER>/<REPO>/<TAG>/tools/ollama-install.sh
sudo chmod +x /tmp/ollama-install.sh
sudo /tmp/ollama-install.sh "<BINARY_URL>" "<SHA256>"
Verify:
bash
sudo systemctl status ollama.service
sudo journalctl -u ollama.service -n 200
curl -fsS http://127.0.0.1:11434/
D. Example output if successful

The installer prints: "[SUCCESS] Ollama installed and responding at http://127.0.0.1:11434/".
The service should be enabled and running: systemctl is-enabled ollama.service → enabled.
Ollama: remote install via vps.sh (automated) Use vps.sh from your local workstation or controller to copy and run the installer on a remote VPS.

Compute SHA256 locally:

bash
BINARY_URL="https://github.com/ollama/ollama/releases/download/vX.Y.Z/ollama-linux-amd64"
SHA256="$(nix-prefetch-url --type sha256 "$BINARY_URL")"
Run the remote installer:

bash
# This command uploads tools/ollama-install.sh to remote /tmp and runs it with sudo
./vps.sh ollama-install ubuntu@203.0.113.5 "$BINARY_URL" "$SHA256"
Verify remotely:

bash
./vps.sh status ubuntu@203.0.113.5
# or from your host:
ssh ubuntu@203.0.113.5 'curl -fsS http://127.0.0.1:11434/ || true; sudo systemctl status ollama.service'
Ollama: Docker alternative If you prefer containerization, the included docker-compose.yml runs Ollama in a container:

Edit docker-compose.yml and pin the image tag (avoid :latest for production).
Start Ollama:
bash
docker-compose up -d
docker-compose logs -f ollama
curl -fsS http://127.0.0.1:11434/
Docker is convenient for isolation and for CI/test runners. The systemd installer is preferred when you want native performance and simpler host-level monitoring.

Reverse proxy + TLS (recommended for public exposure) Do NOT expose Ollama directly to the internet without securing it. Use a reverse proxy (Nginx, Caddy) with TLS and authentication.

A. Nginx example (basic)

Nginx
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
    }
}
Add basic auth or JWT-based auth in front of this if you need access control. Use certbot to obtain Let's Encrypt certs or automate via CI.

B. Caddy example (automatic HTTPS) Caddy automatically manages TLS:

caddy
ollama.example.com {
    reverse_proxy 127.0.0.1:11434
    # Add authentication plugins or middleware as required
}
C. Recommended network flow Clients -> TLS reverse proxy (Nginx/Caddy) -> local Ollama on 127.0.0.1:11434
Firewall on VPS: only allow ports 22 (SSH) and 443 (proxy). Close 11434 to the world.

Model management & storage considerations

Models are stored in Ollama’s data dir (/var/lib/ollama by default).
Model size can be large — ensure the data partition has sufficient space (SSD recommended).
Back up /var/lib/ollama if you need to preserve downloaded models.
For multi-tenant or multi-model setups, consider a dedicated disk or path with sufficient IOPS.
Performance & sizing guidance (real-time LLM)

Small CPU models: 8–16 GB RAM may be usable but expect higher latency.
Medium models: 32+ GB RAM recommended for decent latency.
Large models / high throughput: 64+ GB / GPU required.
Disk: SSD for /var/lib/ollama to reduce I/O stalls.
Swap: prefer avoiding swap; better to add RAM than to rely on swap.
CPU: high single-thread performance helps with latency for non-GPU models.
Monitor memory and CPU; add autoscaling strategies or horizontal scaling if required.
Pinning, SHA256 verification, and CI practices

Always pin raw URLs to a tag/commit. Example: https://raw.githubusercontent.com/youruser/idx-vps-ollama/v1.0.0/tools/ollama-install.sh
For Ollama binary, compute SHA256 and use it when installing.
CI recommendations:
Lint shell scripts (shellcheck).
Format scripts (shfmt).
Optionally include a job that downloads and verifies the pinned Ollama binary (without executing it) to assert release assets are stable.
Monitoring, logs, and troubleshooting Useful commands:

bash
# service & logs
sudo systemctl status ollama.service
sudo journalctl -u ollama.service -f

# health
curl -fsS http://127.0.0.1:11434/

# check disk
df -h /var/lib/ollama

# check binary architecture
file /usr/local/bin/ollama
Common issues:

SHA mismatch: re-download binary and verify; ensure URL exactly matches the release asset used to compute SHA.
Service failing to start: journalctl -u ollama.service -n 200 for stack traces; check that data dir permissions are correct and binary is executable.
Port conflict: ensure 11434 isn't occupied or change port in systemd unit and reverse proxy config.
Insufficient memory: Ollama may crash if OOM; add RAM or run smaller models.
Upgrade, rollback, and maintenance Upgrade process:

bash
# stop
sudo systemctl stop ollama.service

# replace binary (download new pinned binary and verify SHA)
# restart
sudo systemctl daemon-reload
sudo systemctl start ollama.service
Rollback:

Replace binary with previous pinned binary and restart service.
Maintenance tips:

Keep a scheduled snapshot / backup of /var/lib/ollama.
Rotate logs via systemd/journald or external log agent.
Periodically review disk usage and prune unused models if needed.
Security checklist & recommendations

Pin all raw URLs and verify checksums.
Avoid piping remote scripts directly into a shell. Download -> inspect -> execute.
Use SSH keys and disable password authentication for production servers.
Do not store plaintext secrets in config files. Use vaults/secrets managers if possible.
Put Ollama behind a reverse proxy with TLS and authentication.
Restrict direct access to the Ollama port (11434) via firewall rules.
Add monitoring & alerting for CPU, memory, and disk.
Integration with ixd.google.com (raw URL usage) If ixd.google.com loads scripts by raw URL, do the following:

Pin the script to a commit/tag.
Configure ixd to download the script into a sandboxed runner, verify checksum, and run inside an isolated container/VM (not on a production host).
Example import flow (recommended):
ixd downloads tools/ollama-install.sh to workspace,
displays or audits script,
runs install on a controlled test instance (not production),
if successful, runs installer on production VPS via SSH using the vps automation path.
Contributing

Fork and create a branch.
Run format & lint locally:
bash
shfmt -w -i 2 vm.sh vps.sh tools/ollama-install.sh
shellcheck -x vm.sh vps.sh tools/ollama-install.sh
Open a PR describing changes and tests.
License MIT License — see LICENSE file. Replace author/year for your own repo.

Appendix: useful commands & examples Compute sha256 for an Ollama release:

bash
BINARY_URL="https://github.com/ollama/ollama/releases/download/vX.Y.Z/ollama-linux-amd64"
nix-prefetch-url --type sha256 "$BINARY_URL"
# or
curl -fsSL -o /tmp/ollama.bin "$BINARY_URL"
sha256sum /tmp/ollama.bin
Install Ollama remotely via vps.sh (once SHA computed):

bash
./vps.sh ollama-install ubuntu@203.0.113.5 "$BINARY_URL" "<SHA256>"
Check health & logs:

bash
ssh ubuntu@203.0.113.5 'curl -fsS http://127.0.0.1:11434/ || true; sudo systemctl status ollama.service'
Example Nginx + basic auth (production):

Use certbot for TLS and htpasswd/auth_basic for simple auth, or put your auth layer at the edge (Cloudflare, API gateway).
Final notes This README intentionally goes deep into the Ollama install and operational guidance so you can deploy and run LLMs reliably on VPS instances created via vm.sh and managed via vps.sh. If you want, I can:

produce a ready-to-run GitHub Actions release workflow which calculates SHA256 for chosen Ollama binaries and automatically generates release notes,
add a flake.nix that pins Ollama binaries and scripts via fetchurl,
add an example reverse proxy + systemd drop-in for rate-limiting or auth middleware. If you'd like any of the above automated or committed into the repository, tell me which and I will provide the code/CI next.
Code

Next steps — create repository and publish (exact commands)
1) Create the repo directory locally and add files (example assumes you have the other files saved next to README.md):
```bash
mkdir idx-vps-ollama
cd idx-vps-ollama
# create files: README.md (paste above), vm.sh, vps.sh, tools/ollama-install.sh, dev.nix, docker-compose.yml, .github/workflows/ci.yml, CONTRIBUTING.md, LICENSE
Initialize git, commit, and create GitHub repo (using GitHub CLI gh):
bash
git init
git add .
git commit -m "Initial commit: vm, vps, ollama installer, dev.nix, CI, README"
gh repo create <YOUR_GH_USER>/idx-vps-ollama --public --source=. --remote=origin --push
# set repo metadata
gh repo edit <YOUR_GH_USER>/idx-vps-ollama --description "KVM & VPS automation for creating VMs, deploying servers, and installing Ollama (systemd)."
gh repo edit <YOUR_GH_USER>/idx-vps-ollama --add-topic vps kvm qemu cloud-init ollama nix scripts
git tag -a v1.0.0 -m "Initial release"
git push origin v1.0.0
Pin the README raw URL and the script raw URLs in your ixd.google.com integration using the tag/commit you pushed:
Code
https://github.com/kali-X9/idx-vps-ollama.git/<https://github.com/kali-X9>/idx-vps-ollama/v1.0.0/README.md
https://github.com/kali-X9/idx-vps-ollama.git<https://github.com/kali-X9>/idx-vps-ollama/v1.0.0/tools/ollama-install.sh
https://github.com/kali-X9/idx-vps-ollama.git<https://github.com/kali-X9/idx-vps-ollama/v1.0.0/vps.sh
https://github.com/kali-X9/idx-vps-ollama.git<https://github.com/kali-X9>/idx-vps-ollama/v1.0.0/vm.sh
Compute Ollama SHA256 and install on VPS

On your workstation:
bash
BINARY_URL="https://github.com/ollama/ollama/releases/download/vX.Y.Z/ollama-linux-amd64"
SHA256=$(nix-prefetch-url --type sha256 "$BINARY_URL")
# or:
curl -fsSL -o /tmp/ollama.bin "$BINARY_URL"
sha256sum /tmp/ollama.bin
Then run:
bash
./vps.sh ollama-install ubuntu@<VPS_IP> "$BINARY_URL" "$SHA256"




