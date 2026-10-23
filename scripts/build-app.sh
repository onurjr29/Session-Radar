#!/bin/bash
# SessionRadar.app paketini üretir; --install ile /Applications'a kurar ve hook'ları ekler,
# --zip ile evrensel (arm64 + x86_64) build/SessionRadar.zip üretir.
set -euo pipefail
cd "$(dirname "$0")/.."

ARCH_FLAGS=()
if [[ "${1:-}" == "--zip" ]]; then
    ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"
APP=build/SessionRadar.app

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN/SessionRadar" "$BIN/radar-hook" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"

# Supabase ayarı (git'e girmez); yoksa paylaşım yapılandırılmamış kalır.
if [[ -f config/supabase.env ]]; then
    SUPABASE_URL="$(sed -n 's/^SUPABASE_URL=//p' config/supabase.env | head -1)"
    SUPABASE_ANON_KEY="$(sed -n 's/^SUPABASE_ANON_KEY=//p' config/supabase.env | head -1)"
    plutil -replace SupabaseURL -string "$SUPABASE_URL" "$APP/Contents/Info.plist"
    plutil -replace SupabaseAnonKey -string "$SUPABASE_ANON_KEY" "$APP/Contents/Info.plist"
fi

codesign --force --deep -s - "$APP"

if [[ "${1:-}" == "--zip" ]]; then
    ARCHS="$(lipo -archs "$APP/Contents/MacOS/SessionRadar")"
    if [[ "$ARCHS" != *arm64* || "$ARCHS" != *x86_64* ]]; then
        echo "Hata: evrensel derleme beklenirken mimariler: $ARCHS" >&2
        exit 1
    fi
    STAGE="$(mktemp -d)"
    trap 'rm -rf "$STAGE"' EXIT
    mkdir "$STAGE/SessionRadar"
    cp -R "$APP" "$STAGE/SessionRadar/"
    cp scripts/kur.sh "$STAGE/SessionRadar/"
    rm -f build/SessionRadar.zip
    ditto -c -k --norsrc --keepParent "$STAGE/SessionRadar" build/SessionRadar.zip
    echo "Üretildi: build/SessionRadar.zip ($ARCHS)"
fi

if [[ "${1:-}" == "--install" ]]; then
    pkill -x SessionRadar || true
    rm -rf /Applications/SessionRadar.app
    cp -R "$APP" /Applications/
    /Applications/SessionRadar.app/Contents/MacOS/SessionRadar install
    open /Applications/SessionRadar.app
fi
