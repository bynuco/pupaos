#!/bin/sh
# pupaos-session: PupaOS ana oturum başlatıcı

# 1. Güvenli Yol ve Çevre Ayarları
export PATH="/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin"

# 2. XDG_RUNTIME_DIR (sessiz hata kontrolü)
#if [ -z "$XDG_RUNTIME_DIR" ]; then
#    export XDG_RUNTIME_DIR="/tmp/$(id -u)-runtime-dir"
#    mkdir -p "$XDG_RUNTIME_DIR" && chmod 0700 "$XDG_RUNTIME_DIR"
#fi

# 3. Akıllı Donanım/VM Tespiti (Daha geniş kapsamlı)
is_vm() {
    # DMI (BIOS) bilgisi, CPU flagleri veya bilinen hypervisor dosyaları
    grep -qiE "qemu|vmware|virtualbox|vbox|kvm|microsoft" /sys/class/dmi/id/product_name 2>/dev/null || \
    grep -qi "hypervisor" /proc/cpuinfo 2>/dev/null || \
    [ -d /sys/bus/platform/drivers/vboxguest ] 2>/dev/null || \
    lsmod 2>/dev/null | grep -q vboxguest # VirtualBox spesifik check
}

if is_vm; then
    # Sanal makinede donanım hızlandırma çökmelere neden olabilir; yazılımsal renderer kullan.
    export WLR_RENDERER=pixman
    export WLR_NO_HARDWARE_CURSORS=1
elif lsmod 2>/dev/null | grep -q "^nvidia "; then
    # NVIDIA proprietary: Wayland için standart dışı ayarlar gerektirir.
    # nvidia-drm kernel modülü GBM backend sağlar; nvidia-vaapi-driver VA-API'yi üstlenir.
    # Sürücü 555+ ile wlroots explicit sync desteklenir; __GL_SYNC_TO_VBLANK tearing önler.
    export GBM_BACKEND=nvidia-drm
    export __GLX_VENDOR_LIBRARY_NAME=nvidia
    export WLR_NO_HARDWARE_CURSORS=1
    export LIBVA_DRIVER_NAME=nvidia
    export NVD_BACKEND=direct
    export __GL_SYNC_TO_VBLANK=0
fi
# AMD (amdgpu) ve Intel (i915/xe): mesa-vaapi / intel-media-driver standart DRM
# arayüzü üzerinden GPU'yu otomatik tanır; ek ortam değişkeni gerekmez.

# 4. Uygulama Standartları (launcher ve DesktopEntries Flatpak .desktop'ları görsün)
export XDG_DATA_DIRS="${XDG_DATA_DIRS:-/usr/local/share:/usr/share}:/var/lib/flatpak/exports/share:${HOME}/.local/share/flatpak/exports/share"

# 5. Wayland masaüstü (ikon teması: Quickshell + diğer Qt uygulamaları)
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=wayfire
export XDG_SESSION_DESKTOP=wayfire
export MOZ_ENABLE_WAYLAND=1
export QT_QPA_PLATFORM=wayland
export QT_QPA_PLATFORMTHEME=gtk3
export GDK_BACKEND=wayland
export QS_ICON_THEME=Adwaita
#export LIBSEAT_BACKEND=seatd

# 6. Önceki oturum artıklarını temizle
# pkill wayfire sonrası orphan kalan quickshell watchdog loop'u ve process'lerini durdur.
# Önce watchdog sh loop'unu öldür (yoksa quickshell'i hemen yeniden başlatır).
pkill -f "quickshell" 2>/dev/null || true
pkill -x "tty-watchdog" 2>/dev/null || true
sleep 0.5

# Eğer halihazırda bir DBUS oturumu yoksa çalıştır, varsa doğrudan wayfire'ı çalıştır
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    exec dbus-run-session wayfire 
else
    exec wayfire 
fi

