#!/bin/bash
#
# PupaOS - QEMU ile ISO test scripti
# Kullanım: ./test.sh [iso dosyası]
#
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ISO dosyasını bul
if [ -n "${1:-}" ]; then
    ISO="$1"
else
    ISO=$(ls -t "$SCRIPT_DIR"/pupaos-*.iso 2>/dev/null | head -1)
    if [ -z "$ISO" ]; then
        echo "Hata: ISO bulunamadı. Önce sudo ./build-iso.sh çalıştırın." >&2
        echo "       Ya da: ./test.sh /yol/to/dosya.iso" >&2
        exit 1
    fi
fi

if [ ! -f "$ISO" ]; then
    echo "Hata: ISO dosyası bulunamadı: $ISO" >&2
    exit 1
fi

# QEMU kontrol
if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "Hata: qemu-system-x86_64 bulunamadı." >&2
    echo "  sudo xbps-install qemu" >&2
    exit 1
fi

# OVMF (UEFI firmware) bul — EFI boot için
OVMF=""
for f in \
    /usr/share/qemu/OVMF.fd \
    /usr/share/ovmf/OVMF.fd \
    /usr/share/edk2/ovmf/OVMF_CODE.fd; do
    if [ -f "$f" ]; then OVMF="$f"; break; fi
done

echo ">> ISO   : $ISO"

QEMU_ARGS=(
    -enable-kvm
    -cpu host
    -smp 2
    -m 2G
    -vga virtio
    -display sdl,gl=on
    -audiodev pipewire,id=audio0
    -device intel-hda
    -device hda-duplex,audiodev=audio0
    -netdev user,id=net0
    -device virtio-net-pci,netdev=net0
    -cdrom "$ISO"
    -boot d
)

if [ -n "$OVMF" ]; then
    echo ">> UEFI  : $OVMF"
    QEMU_ARGS+=(-drive if=pflash,format=raw,readonly=on,file="$OVMF")
else
    echo ">> UEFI  : bulunamadı, BIOS modunda başlatılıyor"
    echo "   (UEFI için: sudo xbps-install qemu-ovmf-x86_64)"
fi

echo ""
qemu-system-x86_64 "${QEMU_ARGS[@]}"
