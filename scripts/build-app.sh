#!/bin/bash
# SessionRadar.app paketini üretir; --install ile /Applications'a kurar ve hook'ları ekler.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)"
APP=build/SessionRadar.app

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN/SessionRadar" "$BIN/radar-hook" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
codesign --force --deep -s - "$APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x SessionRadar || true
    rm -rf /Applications/SessionRadar.app
    cp -R "$APP" /Applications/
    /Applications/SessionRadar.app/Contents/MacOS/SessionRadar install
    open /Applications/SessionRadar.app
fi
