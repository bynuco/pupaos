#!/bin/bash
#
# PupaOS - Özel canlı ISO oluşturma scripti
# mklive/mklive.sh etrafında ince bir sarmalayıcıdır.
# Root yetkisiyle çalıştırılmalıdır (mklive.sh zaten kontrol eder).
#
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MKLIVE_DIR="$SCRIPT_DIR/void-mklive"
OVERLAY_DIR="$SCRIPT_DIR/overlay"
OUTPUT="$SCRIPT_DIR/pupaos-$(uname -m)-$(date -u +%Y%m%d).iso"

# ---- Ön kontroller ----
if [ "$(id -u)" -ne 0 ]; then
    echo "Hata: sudo ile çalıştırın: sudo $0" >&2; exit 1
fi
if [ ! -x "$MKLIVE_DIR/mklive.sh" ]; then
    echo "Hata: mklive/mklive.sh bulunamadı." >&2; exit 1
fi

# ---- XBPS'ten kurulacak paketler ----
# Not: base-system, agetty, udevd → mklive.sh zaten ekliyor.
# grub paketleri live rootfs'a dahil edilmeli — copy_rootfs ile hedefe kopyalanır.
PKGS=(
    wayfire                     # Wayland compositor
    xorg-server-xwayland        # wayfire.ini: xwayland = true
    swaybg                      # wayfire.ini autostart: arka plan
    foot                        # terminal
    quickshell                  # panel/shell
    qt6-plugin-tls-openssl      # Quickshell launcher HTTPS/TLS (qt.network.ssl)
    mesa mesa-dri mesa-vaapi mesa-vulkan-nouveau mesa-vulkan-radeon  # GPU sürücüleri
    xdg-desktop-portal          # Portal çekirdek (org.freedesktop.portal.Desktop)
    xdg-desktop-portal-gtk      # Portal: dosya seçici vb.
    xdg-desktop-portal-wlr      # Wayland/wlroots: ekran görüntüsü, paylaşım
    xdg-utils                   # xdg-open, xdg-screensaver vb.
    pipewire alsa-pipewire wireplumber              # Ses sistemi
    NetworkManager              # Ağ yönetimi
    elogind                     # libseat: DRM session yönetimi
    polkit dbus                 # Sistem servisleri
    rofi                        # Uygulama başlatıcı
    dejavu-fonts-ttf noto-fonts-ttf terminus-font  # Yazı tipleri
    adwaita-icon-theme          # İkon teması (panel/launcher + tar.gz uygulama varsayılanı)
    dialog                      # pupainstaller için gerekli
    grim                        # Ekran görüntüsü (Wayland)
    slurp                       # Alan seçimi (grim ile kullanılır)
    wl-clipboard                # Wayland pano (wl-copy)
    flatpak                     # Flatpak: sisteme doğrudan dahil
    xmirror                     # Mirror seçimi (pupainstaller menu_mirror)
    grub                        # BIOS kurulumu için GRUB
    grub-x86_64-efi             # EFI 64-bit kurulumu için GRUB
    grub-i386-efi               # EFI 32-bit kurulumu için GRUB
    ffmpeg                      # Video codec desteği (H.264, VP9, AAC vb.)
    mpv                         # Video oynatıcı (Wayland uyumlu)
)

SERVICES="dbus elogind polkitd NetworkManager"

# ---- Include dizini hazırla ----
INCLUDEDIR=$(mktemp -d)
trap 'rm -rf "$INCLUDEDIR"' EXIT INT TERM

# Overlay (wayfire.ini, quickshell QML dosyaları, görseller)
# /etc/skel/ altına koyuyoruz: useradd -m bunu /home/pupa/'a kopyalar.
echo ">> Overlay kopyalanıyor..."
mkdir -p "$INCLUDEDIR/etc/skel"
cp -a "$OVERLAY_DIR/." "$INCLUDEDIR/etc/skel/"

# Quickshell Wayfire yardımcıları (Rust): binary'ler skel'e kopyalanır, kaynak overlay'de değil
QUICKSHELL_BOTTOM="$INCLUDEDIR/etc/skel/.config/quickshell/bottom"
if command -v cargo >/dev/null 2>&1; then
    echo ">> Quickshell Wayfire binary'leri derleniyor..."
    (cd "$SCRIPT_DIR/tools/quickshell-wayfire" && cargo build --release) || { echo "Hata: cargo build başarısız." >&2; exit 1; }
    for bin in wayfire-workspace-windows wayfire-ipc tty-watchdog; do
        install -Dm755 "$SCRIPT_DIR/tools/quickshell-wayfire/target/release/$bin" "$QUICKSHELL_BOTTOM/$bin"
    done
else
    echo "Hata: ISO oluşturmak için Rust (cargo) gerekli. tools/quickshell-wayfire binary'leri derlenemedi." >&2
    exit 1
fi

# Pipewire yapılandırması
# Not: wayfire XDG autostart işlemiyor; pipewire wayfire.ini [autostart]'tan başlar.
echo ">> Pipewire yapılandırılıyor..."
mkdir -p "$INCLUDEDIR/etc/pipewire/pipewire.conf.d"
ln -sf /usr/share/examples/wireplumber/10-wireplumber.conf \
    "$INCLUDEDIR/etc/pipewire/pipewire.conf.d/"
ln -sf /usr/share/examples/pipewire/20-pipewire-pulse.conf \
    "$INCLUDEDIR/etc/pipewire/pipewire.conf.d/"
mkdir -p "$INCLUDEDIR/etc/alsa/conf.d"
ln -sf /usr/share/alsa/alsa.conf.d/50-pipewire.conf \
    "$INCLUDEDIR/etc/alsa/conf.d/"
ln -sf /usr/share/alsa/alsa.conf.d/99-pipewire-default.conf \
    "$INCLUDEDIR/etc/alsa/conf.d/"

# Flathub: ilk açılışta sistem genelinde eklenir, servis bir kez çalışıp kendini kapatır
echo ">> Flathub tek seferlik servisi ekleniyor..."
mkdir -p "$INCLUDEDIR/etc/sv/flathub-once" "$INCLUDEDIR/etc/runit/runsvdir/default"
install -Dm755 /dev/stdin "$INCLUDEDIR/etc/sv/flathub-once/run" <<'FLATHUB_RUN'
#!/bin/sh
# Flathub zaten ekliyse kendini kapat
if flatpak remote-list --system 2>/dev/null | grep -q '^flathub'; then
    touch /etc/sv/flathub-once/down
    rm -f /etc/runit/runsvdir/default/flathub-once
    exit 0
fi
# Ağ hazır olana kadar bekle (maks. 60 saniye)
i=0
while [ $i -lt 60 ]; do
    if xbps-uhelper fetch https://repo-default.voidlinux.org/current/otime >/dev/null 2>&1; then
        rm -f otime
        break
    fi
    rm -f otime
    sleep 1
    i=$((i + 1))
done
# Flathub'ı ekle; başarılıysa servisi kapat, başarısızsa runit yeniden dener
if flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo 2>/dev/null; then
    touch /etc/sv/flathub-once/down
    rm -f /etc/runit/runsvdir/default/flathub-once
fi
exit 0
FLATHUB_RUN
ln -sf ../../sv/flathub-once "$INCLUDEDIR/etc/runit/runsvdir/default/flathub-once"

# Login sonrası wayfire otomatik başlatma (startos.sh kullanarak)
echo ">> Wayfire otomatik başlatma yapılandırılıyor..."
install -Dm755 "$SCRIPT_DIR/startos.sh" "$INCLUDEDIR/usr/local/bin/pupaos-session"
install -Dm644 /dev/stdin "$INCLUDEDIR/etc/skel/.bash_profile" <<'EOF'
if [ -z "$WAYLAND_DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
    exec pupaos-session
fi
EOF

# /etc/os-release
echo ">> os-release yazılıyor..."
install -Dm644 /dev/stdin "$INCLUDEDIR/etc/os-release" <<'EOF'
NAME="PupaOS"
PRETTY_NAME="PupaOS"
ID=pupaos
ID_LIKE=void
ANSI_COLOR="0;38;2;23;147;209"
HOME_URL="https://pupaos.com"
SUPPORT_URL="https://pupaos.com"
BUG_REPORT_URL="https://pupaos.com"
EOF

# installer scripti → /usr/local/bin/pupainstaller
echo ">> pupainstaller kopyalanıyor..."
install -Dm755 "$SCRIPT_DIR/installer.sh" "$INCLUDEDIR/usr/local/bin/pupainstaller"

# Polkit kuralları → wheel grubundaki kullanıcılar oturum geçişi yapabilsin
# (elogind SwitchTo, TTY değiştirme vb. için gerekli)
echo ">> Polkit kuralları yazılıyor..."
install -Dm644 /dev/stdin "$INCLUDEDIR/etc/polkit-1/rules.d/50-pupaos.rules" <<'EOF'
// wheel grubundaki kullanıcılar polkit yöneticisi sayılır (şifre sorarsa wheel'den sorar).
// Canlı sistemde pupaos-live.rules tüm eylemlere şifresiz YES verir;
// kurulum sonrası o dosya silinir ve buradaki addAdminRule geçerli olur.
polkit.addAdminRule(function(action, subject) {
    return ["unix-group:wheel"];
});
EOF

# ---- mklive override dosyaları ----
# mklive bir upstream submodule'dür; değişiklikler overrides/ altında tutulur
# ve build sırasında mklive içine kopyalanır.
echo ">> mklive overrides uygulanıyor..."
OVERRIDES_DIR="$SCRIPT_DIR/overrides"
for f in "dracut/vmklive/adduser.sh" "data/issue"; do
    if [ ! -f "$OVERRIDES_DIR/$f" ]; then
        echo "Hata: Override dosyası yok: $OVERRIDES_DIR/$f" >&2
        exit 1
    fi
done
cp -a "$OVERRIDES_DIR/dracut/vmklive/adduser.sh" "$MKLIVE_DIR/dracut/vmklive/adduser.sh"
cp -a "$OVERRIDES_DIR/data/issue"                "$MKLIVE_DIR/data/issue"

# ---- mklive.sh'ı çalıştır ----
echo ""
echo ">> ISO oluşturuluyor: $OUTPUT"
echo ""

cd "$MKLIVE_DIR"
./mklive.sh \
    -a "$(uname -m)" \
    -o "$OUTPUT" \
    -p "${PKGS[*]}" \
    -S "$SERVICES" \
    -T "PupaOS" \
    -I "$INCLUDEDIR"
