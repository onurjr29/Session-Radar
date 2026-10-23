#!/bin/bash
# Zip'in açıldığı klasörde çalışır: SessionRadar'ı /Applications'a kurar ve hook'ları ekler.
set -euo pipefail
cd "$(dirname "$0")"

if (( $(sw_vers -productVersion | cut -d. -f1) < 14 )); then
    echo "Hata: macOS 14 veya üstü gerekli." >&2
    exit 1
fi

if command -v claude >/dev/null; then
    claude --version
else
    echo "Uyarı: claude komutu bulunamadı; Claude Code kurulana kadar hook'lar çalışmaz."
fi

xattr -dr com.apple.quarantine SessionRadar.app
pkill -x SessionRadar || true
rm -rf /Applications/SessionRadar.app
cp -R SessionRadar.app /Applications/
/Applications/SessionRadar.app/Contents/MacOS/SessionRadar install
open /Applications/SessionRadar.app
