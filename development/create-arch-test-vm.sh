#!/usr/bin/env bash
set -euo pipefail

VM_NAME="${VM_NAME:-arch-veldmuis-test}"
ISO_PATH="${1:-}"
RAM_MB="${RAM_MB:-4096}"
VCPUS="${VCPUS:-4}"
DISK_GB="${DISK_GB:-40}"
CONNECT_URI="${CONNECT_URI:-qemu:///session}"
POOL_DIR="${POOL_DIR:-$HOME/.local/share/libvirt/images}"
DISK_PATH=""
NETWORK_ARGS=()
CREATED_DISK=0

usage() {
  cat <<'EOF'
Usage: create-arch-test-vm.sh /path/to/archlinux.iso

Environment overrides:
  VM_NAME    Default: arch-veldmuis-test
  RAM_MB     Default: 4096
  VCPUS      Default: 4
  DISK_GB    Default: 40
  POOL_DIR   Default: ~/.local/share/libvirt/images
  CONNECT_URI Default: qemu:///session
EOF
}

die() {
  echo "Error: $*" >&2
  exit 1
}

[[ -n "$ISO_PATH" ]] || {
  usage
  exit 1
}

ISO_PATH="$(realpath "$ISO_PATH" 2>/dev/null || true)"
[[ -f "$ISO_PATH" ]] || die "ISO not found: $ISO_PATH"
command -v virt-install >/dev/null 2>&1 || die "virt-install not found"
command -v qemu-img >/dev/null 2>&1 || die "qemu-img not found"
command -v virsh >/dev/null 2>&1 || die "virsh not found"

case "$CONNECT_URI" in
  qemu:///session)
    DISK_PATH="${POOL_DIR}/${VM_NAME}.qcow2"
    NETWORK_ARGS=(--network user,model=virtio)
    ;;
  qemu:///system)
    DISK_PATH="${POOL_DIR}/${VM_NAME}.qcow2"
    NETWORK_ARGS=(--network network=default,model=virtio)
    ;;
  *)
    die "Unsupported CONNECT_URI: $CONNECT_URI"
    ;;
esac

cleanup_on_error() {
  status=$?
  if [[ "$status" -ne 0 && "$CREATED_DISK" -eq 1 ]] && \
    ! virsh --connect "$CONNECT_URI" dominfo "$VM_NAME" >/dev/null 2>&1; then
    rm -f "$DISK_PATH"
  fi
  exit "$status"
}

trap cleanup_on_error EXIT

mkdir -p "$POOL_DIR"

if virsh --connect "$CONNECT_URI" dominfo "$VM_NAME" >/dev/null 2>&1; then
  die "VM already exists: $VM_NAME"
fi

if [[ -e "$DISK_PATH" ]]; then
  die "Disk image already exists: $DISK_PATH"
fi

qemu-img create -f qcow2 "$DISK_PATH" "${DISK_GB}G" >/dev/null
CREATED_DISK=1

virt-install \
  --connect "$CONNECT_URI" \
  --name "$VM_NAME" \
  --memory "$RAM_MB" \
  --vcpus "$VCPUS" \
  --cpu host-passthrough \
  --osinfo detect=on,require=off \
  --cdrom "$ISO_PATH" \
  --disk "path=${DISK_PATH},format=qcow2,bus=virtio" \
  "${NETWORK_ARGS[@]}" \
  --graphics spice \
  --video virtio \
  --channel spicevmc \
  --console pty,target_type=serial \
  --boot uefi \
  --noautoconsole

trap - EXIT
