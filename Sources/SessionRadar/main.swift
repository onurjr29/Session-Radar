import AppKit
import Foundation
import RadarCore
import ServiceManagement
import SwiftUI
import UserNotifications

let settingsURL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/settings.json")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("Hata: \(message)\n".utf8))
    exit(1)
}

func describe(_ error: Error) -> String {
    if case InstallError.unreadableSettings(let m) = error { return m }
    return error.localizedDescription
}

switch CommandLine.arguments.dropFirst().first {
case "install":
    let hook = Bundle.main.executableURL!.deletingLastPathComponent().appending(path: "radar-hook").path
    // ayarlar hiçbir zaman olmayan bir hook binary'sini göstermesin
    guard FileManager.default.isExecutableFile(atPath: hook) else { fail("radar-hook bulunamadı: \(hook)") }
    let paths = RadarPaths.fromEnvironment()
    do {
        try installSettings(at: settingsURL, hookCommand: "\"\(hook)\"")
        for dir in [paths.eventsDir, paths.statusDir, paths.askDir] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    } catch { fail(describe(error)) }
    print("""
    Session Radar kuruldu.
    Ayar dosyası: \(settingsURL.path) (yedek: \(settingsURL.path).session-radar.bak)
    Hook komutu: "\(hook)"
    Hook olayları: \(radarHookEvents.joined(separator: ", "))
    İzinler: \(radarPermissionRules.joined(separator: ", "))
    Veri klasörü: \(paths.root.path)
    """)
    exit(0)
case "uninstall":
    do { try uninstallSettings(at: settingsURL) } catch { fail(describe(error)) }
    print("Session Radar hook'ları ve izinleri kaldırıldı: \(settingsURL.path)")
    exit(0)
default:
    SessionRadarApp.main()
}

struct SessionRadarApp: App {
    private let store = RadarStore()

    init() {
        store.start()
        // swift run ile .app dışında çalışırken bu API'ler kullanılamaz
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        let store = store
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
            guard let error else { return }
            let message = "Bildirim izni alınamadı: \(error.localizedDescription)"
            Task { @MainActor in store.lastError = message }
        }
        // yalnızca ilk açılışta; kullanıcı sonradan kapatırsa yeniden açılmaz
        if !UserDefaults.standard.bool(forKey: "loginItemRegistered") {
            do {
                try SMAppService.mainApp.register()
                UserDefaults.standard.set(true, forKey: "loginItemRegistered")
            } catch {
                store.lastError = "Oturum açılışında başlatma ayarlanamadı: \(error.localizedDescription)"
            }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView(store: store)
        } label: {
            MenuLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuLabel: View {
    let store: RadarStore

    var body: some View {
        let count = badgeCount(store.sessions)
        HStack(spacing: 2) {
            Image(systemName: "dot.radiowaves.left.and.right")
            if count > 0 { Text("\(count)") }
        }
    }
}
