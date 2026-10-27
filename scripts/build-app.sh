#!/bin/bash
# SessionRadar.app paketini üretir; --install ile /Applications'a kurar ve hook'ları ekler,
# --zip ile evrensel (arm64 + x86_64) build/SessionRadar.zip üretir.
set -euo pipefail
cd "$(dirname "$0")/.."

# Supabase ayarı (git'e girmez): --zip'te zorunlu; --install'da yoksa paylaşım yapılandırılmamış kalır.
# Sondaki \r (CRLF) ve çevreleyen tek/çift tırnak atılır.
SUPABASE_URL="" SUPABASE_ANON_KEY=""
if [[ -f config/supabase.env ]]; then
    for k in SUPABASE_URL SUPABASE_ANON_KEY; do
        v="$(sed -n "s/^$k=//p" config/supabase.env | head -1)"
        v="${v%$'\r'}"
        if [[ $v == \"*\" || $v == \'*\' ]]; then v="${v:1:${#v}-2}"; fi
        printf -v "$k" '%s' "$v"
    done
fi

ARCH_FLAGS=()
if [[ "${1:-}" == "--zip" ]]; then
    if [[ -z "$SUPABASE_URL" || -z "$SUPABASE_ANON_KEY" ]]; then
        echo "Hata: --zip için config/supabase.env gerekli ve içinde SUPABASE_URL ile SUPABASE_ANON_KEY dolu olmalı." >&2
        exit 1
    fi
    ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"
APP=build/SessionRadar.app

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/SessionRadar" "$BIN/radar-hook" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"

# İkon (kaynak: scripts/make-icon.swift). macOS 26+ Liquid Glass ikonu .icon'dan Assets.car'a derlenir;
# actool yalnız tam Xcode'da var, yoksa yalnız klasik .icns kullanılır. actool kendi .icns'ini de yazar,
# ardından gelen cp onu klasik çizimle değiştirir.
if xcrun --find actool >/dev/null 2>&1; then
    if ! out="$(xcrun actool Resources/AppIcon.icon --compile "$APP/Contents/Resources" --app-icon AppIcon \
        --platform macosx --minimum-deployment-target 14.0 --output-partial-info-plist build/actool-icon.plist \
        --errors --warnings --output-format human-readable-text)"; then
        echo "$out" >&2
        exit 1
    fi
    rm -f build/actool-icon.plist
    plutil -replace CFBundleIconName -string AppIcon "$APP/Contents/Info.plist"
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

if [[ -f config/supabase.env ]]; then
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
