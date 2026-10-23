#!/bin/sh
# Create and boot a KDE neon VM (KVM + virgl) to test Dock Glass on Plasma.
#
#   sh scripts/vm.sh install   boot the ISO once, to install neon on the disk
#   sh scripts/vm.sh           boot the installed system
#
# Environment overrides: VM_DIR, VM_ISO, VM_RAM (4G), VM_CPUS (4),
# VM_GL (on; set it to off if the window stays black or QEMU fails to start).
#
# Inside the guest:
#   - this project folder is shared with the 9p tag "dockglass":
#       sudo mkdir -p /mnt/dock-glass
#       sudo mount -t 9p -o trans=virtio,version=9p2000.L dockglass /mnt/dock-glass
#   - SSH (after `sudo apt install openssh-server`) is reachable from the host
#     with `ssh -p 2222 <user>@127.0.0.1`.
set -eu

VM_DIR=${VM_DIR:-"$HOME/vms/kde-neon"}
VM_ISO=${VM_ISO:-"$VM_DIR/neon-user-desk-20261018-1825.iso"}
VM_RAM=${VM_RAM:-4G}
VM_CPUS=${VM_CPUS:-4}
VM_GL=${VM_GL:-on}
DISK="$VM_DIR/disk.qcow2"
PROJECT_DIR=$(cd "$(dirname "$0")/.." && pwd)
MODE=${1:-run}

case "$MODE" in
  install | run) ;;
  *) echo "usage: sh scripts/vm.sh [install|run]" >&2; exit 2 ;;
esac

if [ "$MODE" = install ] && [ ! -f "$VM_ISO" ]; then
  echo "No ISO at $VM_ISO." >&2
  exit 1
fi

mkdir -p "$VM_DIR"
if [ ! -f "$DISK" ]; then
  if [ "$MODE" = run ]; then
    echo "No disk at $DISK. Run 'sh scripts/vm.sh install' first." >&2
    exit 1
  fi
  qemu-img create -f qcow2 "$DISK" 40G
fi

set -- -name "Dock Glass - KDE neon" \
  -enable-kvm -machine q35 -cpu host -smp "$VM_CPUS" -m "$VM_RAM" \
  -drive file="$DISK",if=virtio,discard=unmap \
  -nic user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:2222-:22 \
  -virtfs local,path="$PROJECT_DIR",mount_tag=dockglass,security_model=none,id=dockglass \
  -device virtio-tablet-pci -device virtio-keyboard-pci

if [ "$VM_GL" = on ]; then
  set -- "$@" -device virtio-vga-gl -display gtk,gl=on
else
  set -- "$@" -device virtio-vga -display gtk
fi

if [ "$MODE" = install ]; then
  set -- "$@" -cdrom "$VM_ISO" -boot once=d
fi

exec qemu-system-x86_64 "$@"
