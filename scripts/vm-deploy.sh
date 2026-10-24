#!/bin/sh
# Install the plasmoid from package/ and the Plasma Style from plasma-style/
# in the running test VM, then reload Plasma. Choosing the style is left to
# System Settings or `plasma-apply-desktoptheme dockglass`.
#
#   sh scripts/vm-deploy.sh
#
# Needs the VM booted with scripts/vm.sh, a logged-in Plasma session and SSH
# key access. Environment overrides: VM_USER (agustin), VM_PORT (2222),
# VM_SSH_KEY (~/.ssh/dockglass_vm).
set -eu

VM_USER=${VM_USER:-agustin}
VM_PORT=${VM_PORT:-2222}
VM_SSH_KEY=${VM_SSH_KEY:-"$HOME/.ssh/dockglass_vm"}
PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)

tar -C "$PROJECT_DIR" -cf - package plasma-style |
  ssh -i "$VM_SSH_KEY" -p "$VM_PORT" -o BatchMode=yes "$VM_USER@127.0.0.1" '
    set -eu
    src="$HOME/.cache/dockglass-src"
    rm -rf "$src" && mkdir -p "$src" && tar -C "$src" -xf -
    # Upgrade when already installed, install otherwise: type, id, folder.
    put() {
      if kpackagetool6 -t "$1" -s "$2" >/dev/null 2>&1; then
        kpackagetool6 -t "$1" -u "$3"
      else
        kpackagetool6 -t "$1" -i "$3"
      fi
    }
    put Plasma/Applet io.github.atarico.dockglass "$src/package"
    put Plasma/Theme dockglass "$src/plasma-style"
    systemctl --user restart plasma-plasmashell
  '
