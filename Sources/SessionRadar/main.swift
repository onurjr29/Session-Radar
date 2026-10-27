import AppKit
import Foundation
import RadarCore
import ServiceManagement
import SwiftUI
import UserNotifications

// soru sorma süreci stdin'i okumadan çıkarsa uygulama SIGPIPE ile ölmesin
signal(SIGPIPE, SIG_IGN)

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
        try paths.prepareDirectories()
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

/// Panel açıkken uygulama öndedir; delege olmadan banner gösterilmez.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

struct SessionRadarApp: App {
    private let store = RadarStore()
    // merkez delegeyi zayıf tutar
    private let notificationDelegate = NotificationDelegate()

    init() {
        store.start()
        // swift run ile .app dışında çalışırken bu API'ler kullanılamaz
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        let store = store
        UNUserNotificationCenter.current().delegate = notificationDelegate
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
        Window("Session Radar", id: "sessions") {
            SessionWindow(store: store)
                .onAppear { WindowPolicy.opened("sessions") }
                .onDisappear { WindowPolicy.closed("sessions") }
        }
        .defaultSize(width: 980, height: 640)
        Settings {
            TeamSettingsView(store: store)
                .onAppear { WindowPolicy.opened("settings") }
                .onDisappear { WindowPolicy.closed("settings") }
        }
    }
}

/// LSUIElement uygulamaları (.accessory) Stage Manager tarafından yönetilmez; pencere açıkken .regular olur.
/// Küme kullanılır: tekrarlanan onAppear/onDisappear sayacı bozmaz.
@MainActor enum WindowPolicy {
    private static var open: Set<String> = []

    static func opened(_ id: String) {
        open.insert(id)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    static func closed(_ id: String) {
        open.remove(id)
        if open.isEmpty { NSApp.setActivationPolicy(.accessory) }
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
