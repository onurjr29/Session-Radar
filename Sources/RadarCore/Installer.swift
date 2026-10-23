import Foundation

public let radarHookEvents = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Notification", "Stop", "StopFailure", "SessionEnd"]
public let radarPermissionRules = ["Edit(~/.session-radar/status/**)", "Read(~/.session-radar/status/**)"]

public enum InstallError: Error { case unreadableSettings(String) }

private func isOurs(_ hook: Any) -> Bool {
    ((hook as? [String: Any])?["command"] as? String)?.contains("radar-hook") == true
}

// Bize ait hook'ları, izin kurallarını ve boşalan kapları siler; kullanıcıya ait her şey olduğu gibi kalır.
public func unmergeSettings(_ s: [String: Any]) -> [String: Any] {
    var out = s
    if let hooks = s["hooks"] as? [String: Any] {
        var kept: [String: Any] = [:]
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { kept[event] = value; continue }
            let cleaned: [[String: Any]] = groups.compactMap { group in
                guard let inner = group["hooks"] as? [Any] else { return group }
                let rest = inner.filter { !isOurs($0) }
                if rest.count == inner.count { return group }
                if rest.isEmpty { return nil }
                var g = group; g["hooks"] = rest; return g
            }
            if !cleaned.isEmpty { kept[event] = cleaned }
        }
        if kept.isEmpty { out["hooks"] = nil } else { out["hooks"] = kept }
    }
    if var perms = s["permissions"] as? [String: Any], let allow = perms["allow"] as? [String] {
        let rest = allow.filter { !radarPermissionRules.contains($0) }
        if rest.count != allow.count {
            perms["allow"] = rest.isEmpty ? nil : rest
            out["permissions"] = perms.isEmpty ? nil : perms
        }
    }
    return out
}

public func mergeSettings(_ s: [String: Any], hookCommand: String) -> [String: Any] {
    var out = unmergeSettings(s)
    var hooks = out["hooks"] as? [String: Any] ?? [:]
    let ours: [String: Any] = ["hooks": [["type": "command", "command": hookCommand, "timeout": 5] as [String: Any]]]
    for event in radarHookEvents {
        hooks[event] = ((hooks[event] as? [Any]) ?? []) + [ours]
    }
    out["hooks"] = hooks
    var perms = out["permissions"] as? [String: Any] ?? [:]
    var allow = perms["allow"] as? [String] ?? []
    allow += radarPermissionRules.filter { !allow.contains($0) }
    perms["allow"] = allow
    out["permissions"] = perms
    return out
}

// Dosya yoksa boş ayarlar döner; bozuksa ya da nesne değilse fırlatır (hiçbir şey yazılmaz).
private func readSettings(_ url: URL) throws -> [String: Any]? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    do {
        let data = try Data(contentsOf: url)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InstallError.unreadableSettings("JSON nesnesi değil: \(url.path)")
        }
        return obj
    } catch let e as InstallError { throw e }
    catch { throw InstallError.unreadableSettings("\(url.path): \(error.localizedDescription)") }
}

private func writeSettings(_ s: [String: Any], to url: URL, backup: Bool) throws {
    if backup {
        let bak = URL(fileURLWithPath: url.path + ".session-radar.bak")
        try? FileManager.default.removeItem(at: bak)
        try FileManager.default.copyItem(at: url, to: bak)
    }
    let data = try JSONSerialization.data(withJSONObject: s, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    try data.write(to: url, options: .atomic)
}

public func installSettings(at url: URL, hookCommand: String) throws {
    let existing = try readSettings(url)
    try writeSettings(mergeSettings(existing ?? [:], hookCommand: hookCommand), to: url, backup: existing != nil)
}

public func uninstallSettings(at url: URL) throws {
    guard let existing = try readSettings(url) else { return }
    try writeSettings(unmergeSettings(existing), to: url, backup: true)
}
