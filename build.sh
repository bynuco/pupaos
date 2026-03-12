#!/bin/bash

# Hedef dizini ayarlayın. Parametre verilirse oraya, verilmezse mevcut kullanıcının ana dizinine (HOME) kopyalar.
# Eğer tüm sistem dosyalarını (örneğin /etc veya /usr) kopyalamak isterseniz komutu: sudo ./build / şeklinde çalıştırabilirsiniz.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

TARGET_DIR="${1:-$HOME}"
OVERLAY_DIR="$SCRIPT_DIR/overlay"

if [ ! -d "$OVERLAY_DIR" ]; then
    echo "Hata: 'overlay' klasörü bulunamadı: $OVERLAY_DIR" >&2
    exit 1
fi

# Quickshell Wayfire binary'lerini derle ve overlay'a koy (hedefe overlay kopyalanınca gidecek)
OVERLAY_BOTTOM="$OVERLAY_DIR/.config/quickshell/bottom"
if command -v cargo >/dev/null 2>&1 && [ -f "$SCRIPT_DIR/tools/quickshell-wayfire/Cargo.toml" ]; then
    echo "Quickshell Wayfire binary'leri derleniyor..."
    if (cd "$SCRIPT_DIR/tools/quickshell-wayfire" && cargo build --release 2>/dev/null); then
        mkdir -p "$OVERLAY_BOTTOM"
        for bin in wayfire-workspace-windows wayfire-ipc tty-watchdog; do
            if [ -f "$SCRIPT_DIR/tools/quickshell-wayfire/target/release/$bin" ]; then
                cp -f "$SCRIPT_DIR/tools/quickshell-wayfire/target/release/$bin" "$OVERLAY_BOTTOM/$bin"
                chmod 755 "$OVERLAY_BOTTOM/$bin"
            fi
        done
        echo "✅ Binary'ler overlay'a kopyalandı."
    else
        echo "⚠ Cargo derlemesi başarısız; overlay kopyalanacak ama panel script'leri çalışmayabilir." >&2
    fi
else
    echo "⚠ Cargo bulunamadı veya tools/quickshell-wayfire yok; binary'ler atlanıyor." >&2
fi

echo "Overlay '$TARGET_DIR' hedefine kopyalanıyor..."

# Overlay'ı hedefe kopyala (binary'ler dahil)
# --remove-destination: çalışan binary'leri (tty-watchdog vb.) doğrudan üzerine yazmak yerine
# önce siler, sonra yeni dosyayı yazar — "text file busy" hatasını önler.
if ! cp -a --remove-destination "$OVERLAY_DIR/." "$TARGET_DIR/"; then
    echo "❌ Dosyalar kopyalanırken bir hata oluştu." >&2
    exit 1
fi

echo "✅ Bitti. Hedef: $TARGET_DIR"
