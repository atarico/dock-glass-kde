#!/bin/sh
# Install the plasmoid from package/ in the running test VM and reload Plasma.
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

tar -C "$PROJECT_DIR" -cf - package |
  ssh -i "$VM_SSH_KEY" -p "$VM_PORT" -o BatchMode=yes "$VM_USER@127.0.0.1" '
    set -eu
    src="$HOME/.cache/dockglass-src"
    rm -rf "$src" && mkdir -p "$src" && tar -C "$src" -xf -
    if kpackagetool6 -t Plasma/Applet -s io.github.atarico.dockglass >/dev/null 2>&1; then
      kpackagetool6 -t Plasma/Applet -u "$src/package"
    else
      kpackagetool6 -t Plasma/Applet -i "$src/package"
    fi
    systemctl --user restart plasma-plasmashell
  '
