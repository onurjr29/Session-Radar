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
