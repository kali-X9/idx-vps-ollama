#!/usr/bin/env bash
# vps.sh - remote VPS helper utilities (deploy, backup, snapshot, status, remote ollama install)
set -euo pipefail
IFS=$'\n\t'

print_status() {
    local t=$1; shift
    case "$t" in
        INFO)  echo -e "\033[1;34m[INFO]\033[0m $*";;
        WARN)  echo -e "\033[1;33m[WARN]\033[0m $*";;
        ERROR) echo -e "\033[1;31m[ERROR]\033[0m $*" >&2;;
        SUCCESS) echo -e "\033[1;32m[SUCCESS]\033[0m $*";;
        *) echo "[$t] $*";;
    esac
}

usage() {
    cat <<EOF
vps.sh - VPS helper

Usage:
  vps.sh deploy <user@host> <local-dir> <remote-dir>
  vps.sh backup <user@host> <remote-dir> [dest-dir]
  vps.sh snapshot <qcow2-file> <snapshot-name>
  vps.sh status <user@host>
  vps.sh ollama-install <user@host> <BINARY_URL> <SHA256>
EOF
}

cmd_deploy() {
    local target="$1"; local local_dir="$2"; local remote_dir="$3"
    print_status INFO "Deploy $local_dir -> $target:$remote_dir"
    rsync -avz --delete --exclude '.git' --exclude 'node_modules' "$local_dir"/ "$target":"$remote_dir"/
    print_status SUCCESS "Rsync complete"
}

cmd_backup() {
    local target="$1"; local remote_dir="$2"; local out_dir="${3:-./backups}"
    mkdir -p "$out_dir"
    local host=$(echo "$target" | cut -d'@' -f2)
    local stamp; stamp=$(date -u +"%Y%m%dT%H%M%SZ")
    print_status INFO "Backing up $target:$remote_dir -> $out_dir"
    ssh "$target" "set -euo pipefail; mkdir -p /tmp/vps-backup; tar -czf /tmp/vps-backup/${host//./-}-${stamp}.tgz -C '$remote_dir' .; cat /tmp/vps-backup/${host//./-}-${stamp}.tgz" > "${out_dir}/${host//./-}-${stamp}.tgz"
    print_status SUCCESS "Backup saved to ${out_dir}/${host//./-}-${stamp}.tgz"
}

cmd_snapshot() {
    local qcow2="$1"; local snap="$2"
    if [[ ! -f "$qcow2" ]]; then print_status ERROR "qcow2 $qcow2 not found"; return 1; fi
    qemu-img snapshot -c "$snap" "$qcow2"
    print_status SUCCESS "Created snapshot $snap on $qcow2"
}

cmd_status() {
    local target="$1"
    print_status INFO "Checking SSH to $target..."
    if ssh -o BatchMode=yes -o ConnectTimeout=5 "$target" true 2>/dev/null; then
        print_status SUCCESS "SSH OK"
        print_status INFO "Remote disk usage:"
        ssh "$target" "df -hT --total | sed -n '1,10p'"
    else
        print_status ERROR "SSH connection to $target failed"
        return 1
    fi
}

cmd_ollama_install() {
    # usage: vps.sh ollama-install user@host <BINARY_URL> <SHA256>
    local target="$1"; local url="$2"; local sha="$3"
    local local_installer="tools/ollama-install.sh"
    if [[ ! -f "$local_installer" ]]; then print_status ERROR "$local_installer not found in repo"; return 1; fi
    print_status INFO "Copying installer to $target:/tmp/ollama-install.sh"
    scp "$local_installer" "$target":/tmp/ollama-install.sh
    print_status INFO "Running installer on $target (requires sudo on remote)"
    ssh "$target" "sudo bash /tmp/ollama-install.sh '$url' '$sha'"
}

main() {
    if [ $# -lt 1 ]; then usage; exit 1; fi
    local cmd="$1"; shift
    case "$cmd" in
        deploy)  [ $# -eq 3 ] || { usage; exit 1; }; cmd_deploy "$@";;
        backup)  [ $# -ge 2 ] || { usage; exit 1; }; cmd_backup "$@";;
        snapshot)[ $# -eq 2 ] || { usage; exit 1; }; cmd_snapshot "$@";;
        status)  [ $# -eq 1 ] || { usage; exit 1; }; cmd_status "$@";;
        ollama-install) [ $# -eq 3 ] || { usage; exit 1; }; cmd_ollama_install "$@";;
        *) usage; exit 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then main "$@"; fi
