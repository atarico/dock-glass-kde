#!/bin/sh
# Build the Dock Glass Genie KWin effect from kwin-effect/ in the running
# test VM, install it (sudo asks for the VM password) and turn it on. KWin
# never unloads an effect's library, so a rebuilt effect only runs after
# logging out and back in; the first install is loaded at once.
#
#   sh scripts/vm-effect.sh
#
# Needs the build dependencies of a KWin effect in the VM (kwin-dev,
# extra-cmake-modules, qt6-base-dev). Environment overrides: VM_USER
# (agustin), VM_PORT (2222), VM_SSH_KEY (~/.ssh/dockglass_vm).
set -eu

VM_USER=${VM_USER:-agustin}
VM_PORT=${VM_PORT:-2222}
VM_SSH_KEY=${VM_SSH_KEY:-"$HOME/.ssh/dockglass_vm"}
PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)

tar -C "$PROJECT_DIR" --exclude=kwin-effect/build -cf - kwin-effect |
  ssh -i "$VM_SSH_KEY" -p "$VM_PORT" -o BatchMode=yes "$VM_USER@127.0.0.1" '
    set -eu
    src="$HOME/.cache/dockglass-src"
    rm -rf "$src/kwin-effect" && mkdir -p "$src" && tar -C "$src" -xf -
    cd "$src/kwin-effect"
    cmake -B build -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release >/dev/null
    cmake --build build
  '
# A terminal of its own, so sudo can ask for the password.
ssh -i "$VM_SSH_KEY" -p "$VM_PORT" -t "$VM_USER@127.0.0.1" '
    set -eu
    sudo cmake --install "$HOME/.cache/dockglass-src/kwin-effect/build"
    export XDG_RUNTIME_DIR=/run/user/$(id -u)
    export DBUS_SESSION_BUS_ADDRESS=unix:path=$XDG_RUNTIME_DIR/bus
    # On at every login too. After a KWin update, rebuild before logging in.
    kwriteconfig6 --file kwinrc --group Plugins --key dockglassgenieEnabled true
    effects="qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects"
    if [ "$($effects.isEffectLoaded dockglassgenie)" = true ]; then
      echo "Installed. KWin is still running the previous build: log out and back in to load this one."
    else
      $effects.loadEffect dockglassgenie >/dev/null
      echo "dockglassgenie loaded: $($effects.isEffectLoaded dockglassgenie)"
    fi
  '
