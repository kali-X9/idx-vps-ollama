{ pkgs ? import <nixpkgs> {} }:

let
  vmScript = pkgs.writeScriptBin "vm" (builtins.readFile ./vm.sh);
  vpsScript = pkgs.writeScriptBin "vps" (builtins.readFile ./vps.sh);
in
pkgs.mkShell {
  name = "idx-vps-dev-shell";
  buildInputs = [
    pkgs.wget
    pkgs.qemu_kvm
    pkgs.qemu
    pkgs.qemu_utils
    pkgs.cloud-image-utils
    pkgs.openssl
    pkgs.rsync
    pkgs.openssh
    pkgs.curl
    vmScript
    vpsScript
  ];

  shellHook = ''
    echo "dev-shell ready — commands: vm, vps"
    echo "Tip: run ./tools/ollama-install.sh <BINARY_URL> <SHA256> as root on a VPS to install Ollama (non-docker)"
  '';
}
