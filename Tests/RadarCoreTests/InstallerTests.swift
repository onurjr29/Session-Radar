import Testing
import Foundation
@testable import RadarCore

private var user: [String: Any] { ["theme": "dark",
    "permissions": ["allow": ["Bash(ls:*)"], "defaultMode": "auto"],
    "hooks": ["PreToolUse": [["matcher": "Bash", "hooks": [["type": "command", "command": "~/x.sh"]]]]]] }
private func canon(_ d: [String: Any]) -> String { String(decoding: try! JSONSerialization.data(withJSONObject: d, options: .sortedKeys), as: UTF8.self) }

@Test func mergePreservesUserContent() throws {
    let m = mergeSettings(user, hookCommand: "\"/A/radar-hook\"")
    let hooks = try #require(m["hooks"] as? [String: [[String: Any]]])
    #expect(m["theme"] as? String == "dark" && Set(hooks.keys) == Set(radarHookEvents))
    #expect(hooks["PreToolUse"]?.count == 2)
    #expect((m["permissions"] as? [String: Any])?["allow"] as? [String] == ["Bash(ls:*)"] + radarPermissionRules)
}
@Test func mergeIsIdempotent() {
    let once = mergeSettings(user, hookCommand: "\"/A/radar-hook\"")
    #expect(canon(mergeSettings(once, hookCommand: "\"/A/radar-hook\"")) == canon(once))
}
@Test func unmergeRestoresOriginal() {
    #expect(canon(unmergeSettings(mergeSettings(user, hookCommand: "\"/A/radar-hook\""))) == canon(user))
}
@Test func installRefusesMalformedFile() throws {
    let url = try tempFile("{ bozuk")
    #expect(throws: InstallError.self) { try installSettings(at: url, hookCommand: "x/radar-hook") }
    #expect(try String(contentsOf: url, encoding: .utf8) == "{ bozuk")
    #expect(!FileManager.default.fileExists(atPath: url.path + ".session-radar.bak"))
}
@Test func installCreatesMissingFile() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".json")
    try installSettings(at: url, hookCommand: "x/radar-hook")
    let d = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    #expect((d?["hooks"] as? [String: Any])?.count == radarHookEvents.count)
}
@Test func installRefusesUnexpectedShapes() throws {
    for bad in ["{\"hooks\": \"x\"}", "{\"permissions\": {\"allow\": \"x\"}}"] {
        let url = try tempFile(bad)
        #expect(throws: InstallError.self) { try installSettings(at: url, hookCommand: "x/radar-hook") }
        #expect(try String(contentsOf: url, encoding: .utf8) == bad)
        #expect(!FileManager.default.fileExists(atPath: url.path + ".session-radar.bak"))
    }
}
@Test func mergeKeepsNonStringAllowEntries() {
    let s: [String: Any] = ["permissions": ["allow": ["Bash(ls:*)", 42] as [Any]]]
    let m = mergeSettings(s, hookCommand: "x/radar-hook")
    let allow = (m["permissions"] as? [String: Any])?["allow"] as? [Any] ?? []
    #expect(allow.contains { ($0 as? Int) == 42 })
    #expect(Set(allow.compactMap { $0 as? String }) == Set(["Bash(ls:*)"] + radarPermissionRules))
    #expect(canon(unmergeSettings(m)) == canon(s))
}
@Test func backupKeepsOriginal() throws {
    let url = try tempFile("{\"a\": 1}")
    try installSettings(at: url, hookCommand: "x/radar-hook")
    try installSettings(at: url, hookCommand: "x/radar-hook")
    #expect(try String(contentsOfFile: url.path + ".session-radar.bak", encoding: .utf8) == "{\"a\": 1}")
}
