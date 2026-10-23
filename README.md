# Session Radar

Bu makinedeki Claude Code session'larını menü çubuğundan canlı izleyen macOS uygulaması (macOS 14+).

**Kurulum:** `scripts/build-app.sh --install` — uygulamayı derleyip `/Applications/SessionRadar.app` olarak kurar, `~/.claude/settings.json` dosyasına hook'ları ve iki izin kuralını ekler (ilk yedek: `~/.claude/settings.json.session-radar.bak`) ve uygulamayı başlatır. Kurulumdan önce açılmış session'lar yeniden başlatılınca hook olayı göndermeye başlar.

**Kaldırma:**

    /Applications/SessionRadar.app/Contents/MacOS/SessionRadar uninstall
    pkill -x SessionRadar; rm -rf /Applications/SessionRadar.app

**Veriler:** Hepsi `~/.session-radar` altında: `events/` (hook olay günlükleri), `status/` (session durum dosyaları), `ask/` ("Soru sor" çağrılarının çalışma klasörü). 7 günden eski dosyalar açılışta silinir. Hiçbir sunucuya veri yazılmaz; yalnızca "Soru sor", `claude -p` ile aboneliğin üzerinden Haiku'ya sorar.
