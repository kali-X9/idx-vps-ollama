#!/usr/bin/env bash
# tools/ollama-install.sh
# Idempotent installer for Ollama (non-Docker). Must run as root (sudo).
# Usage: sudo ./ollama-install.sh <BINARY_URL> <SHA256>
set -euo pipefail
IFS=$'\n\t'

if [ "$#" -lt 2 ]; then
  echo "Usage: $0 <BINARY_URL> <SHA256>"
  exit 2
fi

BINARY_URL="$1"
EXPECTED_SHA256="$2"
INSTALL_BIN="/usr/local/bin/ollama"
DATA_DIR="/var/lib/ollama"
OLLAMA_USER="ollama"
SERVICE_FILE="/etc/systemd/system/ollama.service"
PORT="${PORT:-11434}"
TMPF="$(mktemp)"

cleanup() { rm -f "$TMPF"; }
trap cleanup EXIT

if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
  echo "[ERROR] curl or wget required." >&2
  exit 3
fi

echo "[INFO] Downloading Ollama binary from: $BINARY_URL"
if command -v curl >/dev/null 2>&1; then
  curl -fsSL -o "$TMPF" "$BINARY_URL"
else
  wget -qO "$TMPF" "$BINARY_URL"
fi

echo "[INFO] Verifying sha256..."
sha256sum_out=$(sha256sum "$TMPF" | awk '{print $1}')
if [ "$sha256sum_out" != "$EXPECTED_SHA256" ]; then
  echo "[ERROR] SHA256 mismatch. Expected: $EXPECTED_SHA256, got: $sha256sum_out" >&2
  exit 4
fi

echo "[INFO] Installing binary to $INSTALL_BIN"
install -m 0755 "$TMPF" "$INSTALL_BIN"

if ! id -u "$OLLAMA_USER" >/dev/null 2>&1; then
  echo "[INFO] Creating user: $OLLAMA_USER"
  useradd --system --no-create-home --shell /usr/sbin/nologin "$OLLAMA_USER" || true
fi

mkdir -p "$DATA_DIR"
chown -R "$OLLAMA_USER:$OLLAMA_USER" "$DATA_DIR"
chmod 750 "$DATA_DIR"

echo "[INFO] Writing systemd service to $SERVICE_FILE"
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Ollama LLM Server
After=network.target

[Service]
User=$OLLAMA_USER
Group=$OLLAMA_USER
Type=simple
ExecStart=$INSTALL_BIN server --port $PORT --data-dir $DATA_DIR
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

echo "[INFO] Enabling and starting service"
systemctl daemon-reload
systemctl enable --now ollama.service

echo "[INFO] Waiting for Ollama health on http://127.0.0.1:$PORT/ (timeout 60s)"
timeout=60; elapsed=0
while ! curl -fsS "http://127.0.0.1:${PORT}/" >/dev/null 2>&1; do
  sleep 2
  elapsed=$((elapsed+2))
  if [ "$elapsed" -ge "$timeout" ]; then
    echo "[WARN] Ollama did not respond within ${timeout}s. Check 'journalctl -u ollama.service -n 200' and 'systemctl status ollama.service'" >&2
    exit 5
  fi
done

echo "[SUCCESS] Ollama installed and responding at http://127.0.0.1:${PORT}/"
exit 0
