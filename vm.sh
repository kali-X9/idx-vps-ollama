#!/usr/bin/env bash
# vm.sh - create/manage KVM cloud-image VMs using qemu + cloud-init
# Requirements: qemu-system-x86_64, qemu-img, wget, cloud-localds (cloud-image-utils), openssl
set -euo pipefail
IFS=$'\n\t'

VM_DIR="${VM_DIR:-$HOME/vms}"
IMG_DIR="${VM_DIR}/images"
mkdir -p "$IMG_DIR"

# Supported OS list: key -> "OS_TYPE|CODENAME|IMG_URL|DEFAULT_HOSTNAME|DEFAULT_USERNAME|DEFAULT_PASSWORD"
declare -A OS_OPTIONS=(
    ["Ubuntu 22.04"]="ubuntu|jammy|https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img|ubuntu22|ubuntu|ubuntu"
    ["Ubuntu 24.04"]="ubuntu|noble|https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img|ubuntu24|ubuntu|ubuntu"
    ["Debian 11"]="debian|bullseye|https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-generic-amd64.qcow2|debian11|debian|debian"
    ["Debian 12"]="debian|bookworm|https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2|debian12|debian|debian"
    ["Fedora 40"]="fedora|40|https://download.fedoraproject.org/pub/fedora/linux/releases/40/Cloud/x86_64/images/Fedora-Cloud-Base-40-1.14.x86_64.qcow2|fedora40|fedora|fedora"
    ["CentOS Stream 9"]="centos|stream9|https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2|centos9|centos|centos"
    ["AlmaLinux 9"]="almalinux|9|https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2|almalinux9|alma|alma"
    ["Rocky Linux 9"]="rockylinux|9|https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud.latest.x86_64.qcow2|rocky9|rocky|rocky"
)

print_status() {
    local type=$1; shift
    local message="$*"
    case "$type" in
        INFO)  echo -e "\033[1;34m[INFO]\033[0m $message" ;;
        WARN)  echo -e "\033[1;33m[WARN]\033[0m $message" ;;
        ERROR) echo -e "\033[1;31m[ERROR]\033[0m $message" >&2 ;;
        SUCCESS) echo -e "\033[1;32m[SUCCESS]\033[0m $message" ;;
        INPUT) echo -e "\033[1;36m[INPUT]\033[0m $message" ;;
        *) echo "[$type] $message" ;;
    esac
}

validate_input() {
    local type=$1; local value=$2
    case "$type" in
        number)  [[ "$value" =~ ^[0-9]+$ ]] || { print_status ERROR "Must be a number"; return 1; } ;;
        size)    [[ "$value" =~ ^[0-9]+[GgMm]$ ]] || { print_status ERROR "Must be a size with unit (e.g., 20G)"; return 1; } ;;
        port)    [[ "$value" =~ ^[0-9]+$ ]] || { print_status ERROR "Must be numeric port"; return 1; }
                 [ "$value" -ge 23 ] && [ "$value" -le 65535 ] || { print_status ERROR "Port must be between 23 and 65535"; return 1; } ;;
        name)    [[ "$value" =~ ^[a-zA-Z0-9_-]+$ ]] || { print_status ERROR "VM name invalid"; return 1; } ;;
        username)[[ "$value" =~ ^[a-z_][a-z0-9_-]*$ ]] || { print_status ERROR "Username invalid"; return 1; } ;;
        *) print_status WARN "Unknown validate type: $type"; return 1 ;;
    esac
    return 0
}

check_dependencies() {
    local deps=(qemu-system-x86_64 wget cloud-localds qemu-img openssl)
    local miss=()
    for d in "${deps[@]}"; do
        if ! command -v "$d" &>/dev/null; then miss+=("$d"); fi
    done
    if [ ${#miss[@]} -ne 0 ]; then
        print_status ERROR "Missing dependencies: ${miss[*]}"
        print_status INFO "On Debian/Ubuntu: sudo apt update && sudo apt install -y qemu-system-x86 qemu-utils cloud-image-utils wget openssl"
        exit 1
    fi
}

get_vm_list() {
    find "$VM_DIR" -maxdepth 1 -name "*.conf" -exec basename {} .conf \; 2>/dev/null | sort
}

load_vm_config() {
    local vm_name=$1
    local cfg="$VM_DIR/$vm_name.conf"
    if [[ -f "$cfg" ]]; then
        # shellcheck disable=SC1090
        source "$cfg"
        return 0
    fi
    print_status ERROR "Configuration $cfg not found"
    return 1
}

save_vm_config() {
    local cfg="$VM_DIR/$VM_NAME.conf"
    cat > "$cfg" <<EOF
VM_NAME="$VM_NAME"
OS_TYPE="$OS_TYPE"
CODENAME="$CODENAME"
IMG_URL="$IMG_URL"
HOSTNAME="$HOSTNAME"
USERNAME="$USERNAME"
PASSWORD="$PASSWORD"
DISK_SIZE="$DISK_SIZE"
MEMORY="$MEMORY"
CPUS="$CPUS"
SSH_PORT="$SSH_PORT"
IMG_FILE="$IMG_FILE"
SEED_FILE="$SEED_FILE"
CREATED="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
EOF
    print_status SUCCESS "Saved configuration to $cfg"
}

create_new_vm() {
    print_status INFO "Creating new VM"
    local options=(); local i=1
    for k in "${!OS_OPTIONS[@]}"; do echo "  $i) $k"; options[$i]="$k"; ((i++)); done

    local choice sel
    while true; do
        print_status INPUT "Enter choice (1-${#options[@]}):"
        read -r choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#options[@]} ]; then
            sel="${options[$choice]}"
            IFS='|' read -r OS_TYPE CODENAME IMG_URL DEFAULT_HOSTNAME DEFAULT_USERNAME DEFAULT_PASSWORD <<< "${OS_OPTIONS[$sel]}"
            break
        fi
        print_status ERROR "Invalid selection"
    done

    while true; do
        print_status INPUT "VM name (default: $DEFAULT_HOSTNAME):"
        read -r VM_NAME
        VM_NAME="${VM_NAME:-$DEFAULT_HOSTNAME}"
        validate_input name "$VM_NAME" && break
    done

    HOSTNAME="$VM_NAME"

    while true; do
        print_status INPUT "Username (default: $DEFAULT_USERNAME):"
        read -r USERNAME
        USERNAME="${USERNAME:-$DEFAULT_USERNAME}"
        validate_input username "$USERNAME" && break
    done

    while true; do
        print_status INPUT "Password (leave empty to use default):"
        read -r -s PASSWORD
        echo
        PASSWORD="${PASSWORD:-$DEFAULT_PASSWORD}"
        [ -n "$PASSWORD" ] && break
    done

    while true; do
        print_status INPUT "Disk size (e.g., 20G) [20G]:"
        read -r DISK_SIZE
        DISK_SIZE="${DISK_SIZE:-20G}"
        validate_input size "$DISK_SIZE" && break
    done

    while true; do
        print_status INPUT "Memory MB (e.g., 2048) [2048]:"
        read -r MEMORY
        MEMORY="${MEMORY:-2048}"
        validate_input number "$MEMORY" && break
    done

    while true; do
        print_status INPUT "vCPUs [2]:"
        read -r CPUS
        CPUS="${CPUS:-2}"
        validate_input number "$CPUS" && break
    done

    while true; do
        print_status INPUT "Host SSH port to forward to VM's 22 [2222]:"
        read -r SSH_PORT
        SSH_PORT="${SSH_PORT:-2222}"
        validate_input port "$SSH_PORT" && break
    done

    local base_img_basename
    base_img_basename=$(basename "$IMG_URL")
    local base_img="$IMG_DIR/$base_img_basename"
    IMG_FILE="$VM_DIR/${VM_NAME}.qcow2"
    SEED_FILE="$VM_DIR/${VM_NAME}-seed.iso"

    if [[ ! -f "$base_img" ]]; then
        print_status INFO "Downloading base image to $base_img"
        wget -c -O "$base_img" "$IMG_URL"
    else
        print_status INFO "Base image present: $base_img"
    fi

    if [[ -f "$IMG_FILE" ]]; then
        print_status WARN "VM image $IMG_FILE exists. Skipping creation."
    else
        print_status INFO "Creating overlay qcow2 $IMG_FILE (backing: $base_img)"
        qemu-img create -f qcow2 -b "$base_img" "$IMG_FILE" "$DISK_SIZE"
    fi

    local user_data_file="$VM_DIR/${VM_NAME}-user-data"
    local meta_data_file="$VM_DIR/${VM_NAME}-meta-data"
    local enc_pass
    enc_pass=$(printf "%s" "$PASSWORD" | openssl passwd -6 -stdin)

    cat > "$user_data_file" <<EOF
#cloud-config
users:
  - name: $USERNAME
    passwd: $enc_pass
    lock_passwd: false
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
hostname: $HOSTNAME
ssh_pwauth: true
chpasswd:
  list: |
    $USERNAME:$PASSWORD
  expire: False
EOF

    cat > "$meta_data_file" <<EOF
instance-id: $VM_NAME
local-hostname: $HOSTNAME
EOF

    if [[ -f "$SEED_FILE" ]]; then rm -f "$SEED_FILE"; fi
    print_status INFO "Creating seed ISO $SEED_FILE"
    cloud-localds -v "$SEED_FILE" "$user_data_file" "$meta_data_file"

    print_status INFO "Starting VM in background..."
    qemu-system-x86_64 \
        -enable-kvm \
        -m "${MEMORY}M" \
        -smp "${CPUS}" \
        -drive file="$IMG_FILE,format=qcow2,if=virtio" \
        -drive file="$SEED_FILE,format=raw,if=virtio,media=cdrom" \
        -netdev user,id=net0,hostfwd=tcp::${SSH_PORT}-:22 \
        -device virtio-net-pci,netdev=net0 \
        -nographic \
        -daemonize

    sleep 1
    save_vm_config
    print_status SUCCESS "VM '$VM_NAME' created. Connect: ssh $USERNAME@localhost -p $SSH_PORT"
}

start_vm() {
    print_status INPUT "Enter VM name to start:"
    read -r VM_NAME
    if ! load_vm_config "$VM_NAME"; then return 1; fi
    if [[ ! -f "$IMG_FILE" ]]; then print_status ERROR "Image $IMG_FILE missing"; return 1; fi

    print_status INFO "Starting $VM_NAME..."
    if [[ -f "$SEED_FILE" ]]; then
        qemu-system-x86_64 -enable-kvm -m "${MEMORY}M" -smp "${CPUS}" \
            -drive file="$IMG_FILE,format=qcow2,if=virtio" \
            -drive file="$SEED_FILE,format=raw,if=virtio,media=cdrom" \
            -netdev user,id=net0,hostfwd=tcp::${SSH_PORT}-:22 \
            -device virtio-net-pci,netdev=net0 -nographic -daemonize
    else
        qemu-system-x86_64 -enable-kvm -m "${MEMORY}M" -smp "${CPUS}" \
            -drive file="$IMG_FILE,format=qcow2,if=virtio" \
            -netdev user,id=net0,hostfwd=tcp::${SSH_PORT}-:22 \
            -device virtio-net-pci,netdev=net0 -nographic -daemonize
    fi

    print_status SUCCESS "Started VM $VM_NAME (ssh port $SSH_PORT)"
}

delete_vm() {
    print_status WARN "Enter VM name to delete:"
    read -r VM_NAME
    if ! load_vm_config "$VM_NAME"; then return 1; fi
    print_status WARN "Really delete $VM_NAME and files? (yes/NO):"
    read -r confirm
    if [[ "$confirm" != "yes" ]]; then print_status INFO "Aborted"; return 0; fi

    rm -fv "$IMG_FILE" "$SEED_FILE" "$VM_DIR/${VM_NAME}-user-data" "$VM_DIR/${VM_NAME}-meta-data" "$VM_DIR/${VM_NAME}.conf" || true
    print_status SUCCESS "Deleted $VM_NAME"
}

display_header() {
    cat <<'EOF'
========================================================================
Sponsor By These Guys!
HOPINGBOYZ
Jishnu
NotGamerPie
========================================================================
EOF
}

menu() {
    while true; do
        cat <<'MENU'
======================================
 VM manager
 1) Create new VM
 2) List VMs
 3) Start VM
 4) Delete VM
 5) Exit
======================================
MENU
        print_status INPUT "Choice:"
        read -r opt
        case "$opt" in
            1) create_new_vm ;;
            2) get_vm_list | sed -n '1,200p' ;;
            3) start_vm ;;
            4) delete_vm ;;
            5) print_status INFO "Bye"; exit 0 ;;
            *) print_status ERROR "Invalid option" ;;
        esac
    done
}

main() {
    check_dependencies
    display_header
    menu
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then main "$@"; fi
