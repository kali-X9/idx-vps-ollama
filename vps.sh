#!/bin/bash
# Menu-driven VPS Manager for idx-vps-ollama
# Author: kali-X9
# Updated: $(date +%Y-%m-%d)

set -eo pipefail

# Constants
VPS_REQUIRED_RAM=48  # in GB
VPS_REQUIRED_SSD=120 # in GB

# COLORS for better visuals
GREEN='\033[1;32m'
CYAN='\033[1;36m'
RED='\033[1;31m'
NC='\033[0m' # No Color

# Ensure the script runs as root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[ERROR] Please run this script as root.${NC}"
  exit 1
fi

# Menu header/logo
function banner() {
  clear
  echo -e "${CYAN}"
  echo "###################################################"
  echo "#               idx-vps-ollama                    #"
  echo "#      Autonomous VPS Setup and Management        #"
  echo "###################################################"
  echo -e "${NC}"
}

# Verify System Config Requirements (48GB RAM, 120GB Disk)
function verify_system_requirements() {
  echo -e "${GREEN}[INFO] Verifying system requirements...${NC}"
  
  AVAILABLE_RAM=$(free -g | awk '/^Mem:/{print $2}')
  AVAILABLE_DISK=$(df --output=avail -BG / | tail -n 1 | grep -o '[0-9]*')

  if (( AVAILABLE_RAM < VPS_REQUIRED_RAM )); then
    echo -e "${RED}[ERROR] Minimum RAM required: ${VPS_REQUIRED_RAM} GB. Available: ${AVAILABLE_RAM} GB.${NC}"
    exit 1
  fi

  if (( AVAILABLE_DISK < VPS_REQUIRED_SSD )); then
    echo -e "${RED}[ERROR] Minimum SSD required: ${VPS_REQUIRED_SSD} GB. Available: ${AVAILABLE_DISK} GB.${NC}"
    exit 1
  fi

  echo -e "${GREEN}[SUCCESS] System requirements satisfied.${NC}"
}

# Install Dependencies
function install_dependencies() {
  echo -e "${GREEN}[INFO] Installing dependencies...${NC}"

  apt-get update
  apt-get install -y qemu-kvm libvirt-daemon-system libvirt-clients curl jq shellcheck shfmt

  echo -e "${GREEN}[SUCCESS] All dependencies installed.${NC}"
}

# Create a New VM
function create_vm() {
  echo -e "${CYAN}Enter the following details for your VM:${NC}"
  echo -n "VM Name: "
  read VM_NAME

  echo -n "Cloud Image Path (e.g., ubuntu-cloud.img): "
  read VM_IMAGE

  echo -e "${GREEN}[INFO] Creating VM '${VM_NAME}' using image '${VM_IMAGE}'...${NC}"
  ./vm.sh create --name "$VM_NAME" --image "$VM_IMAGE" --cpus 4 --memory 8192
  echo -e "${GREEN}[SUCCESS] VM '${VM_NAME}' created.${NC}"
}

# Deploy to VPS
function deploy_ollama() {
  echo -e "${CYAN}Enter VPS details for deployment:${NC}"
  echo -n "SSH User (e.g., ubuntu): "
  read SSH_USER
  echo -n "VPS IP Address: "
  read VPS_IP
  echo -e "${GREEN}[INFO] Deploying Ollama to VPS at '${SSH_USER}@${VPS_IP}'...${NC}"
  
  # Transfer and install Ollama remotely
  ./vps.sh deploy --host "${SSH_USER}@${VPS_IP}" --key ~/.ssh/id_rsa --script tools/ollama-install.sh
  echo -e "${GREEN}[SUCCESS] Ollama deployed successfully.${NC}"
}

# Real-time Monitoring
function monitor_vps() {
  echo -e "${CYAN}Enter VPS details to monitor:${NC}"
  echo -n "SSH User (e.g., ubuntu): "
  read SSH_USER
  echo -n "VPS IP Address: "
  read VPS_IP
  echo -e "${GREEN}[INFO] Fetching real-time stats...${NC}"

  ssh "${SSH_USER}@${VPS_IP}" 'top -b -n 1 | head -n 20'
  echo -e "${GREEN}[INFO] Real-time stats displayed.${NC}"
}

# Main Menu
function main_menu() {
  while true; do
    banner
    echo -e "${CYAN}Main Menu${NC}"
    echo "1. Verify System Requirements"
    echo "2. Install Dependencies"
    echo "3. Create New VM"
    echo "4. Deploy Ollama on VPS"
    echo "5. Monitor VPS in Real-Time"
    echo "6. Exit"
    echo -n "Enter your choice: "
    read CHOICE
    
    case $CHOICE in
      1) verify_system_requirements ;;
      2) install_dependencies ;;
      3) create_vm ;;
      4) deploy_ollama ;;
      5) monitor_vps ;;
      6) echo -e "${GREEN}Exiting... Goodbye!${NC}"; exit 0 ;;
      *) echo -e "${RED}[ERROR] Invalid choice. Try again.${NC}" ;;
    esac
    read -n 1 -s -r -p "Press any key to return to the menu..."
  done
}

# Start Menu System
main_menu
