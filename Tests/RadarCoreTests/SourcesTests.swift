import Testing
import Foundation
@testable import RadarCore

func tempFile(_ content: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try content.write(to: url, atomically: true, encoding: .utf8)
    return url
}

let fixture = """
{"type":"ai-title","aiTitle":"Giriş ekranı hatası","sessionId":"s1"}
{"type":"user","isMeta":false,"message":{"role":"user","content":"Login butonu çalışmıyor, düzelt"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Bakıyorum."},{"type":"tool_use","id":"t1","name":"Edit","input":{"file_path":"/r/Login.tsx","old_string":"a","new_string":"b"}}]}}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"ok"}]}}
{"type":"last-prompt","lastPrompt":"Login butonu çalışmıyor, düzelt","sessionId":"s1"}
"""

@Test func transcriptTailExtractsInfo() throws {
    let url = try tempFile(fixture)
    let t = readTranscriptTail(url)
    #expect(t.aiTitle == "Giriş ekranı hatası" && t.lastPrompt == "Login butonu çalışmıyor, düzelt")
    #expect(t.lastAction == "Edit · Login.tsx")
    #expect(t.dialogue == ["Kullanıcı: Login butonu çalışmıyor, düzelt", "Claude: Bakıyorum."])
}
@Test func transcriptTailSurvivesCutLine() throws {
    let t = readTranscriptTail(try tempFile(fixture), maxBytes: 120)
    #expect(t.lastPrompt == "Login butonu çalışmıyor, düzelt")
}
@Test func agentsParsing() {
    let json = #"[{"id":"eb81","cwd":"/r","kind":"background","startedAt":1,"sessionId":"a","name":"n","state":"blocked"},{"pid":23183,"cwd":"/r","kind":"interactive","startedAt":2,"sessionId":"b","name":"mobile-worker","status":"idle"}]"#
    let a = parseAgents(Data(json.utf8))
    #expect(a.count == 2 && a[0].pid == nil && a[1].pid == 23183 && a[1].status == "idle")
    #expect(parseAgents(Data("garbage".utf8)).isEmpty)
}
@Test func statusLoadingIsTolerant() throws {
    let s = loadStatus(try tempFile(#"{"task":"Login düzelt","todo":[{"text":"a","done":true}],"topics":[{"title":"Giriş","state":"done"},{"title":"Login","state":"active"}],"extra":1}"#))
    #expect(s?.task == "Login düzelt" && s?.todo?.first?.done == true && s?.why == nil)
    #expect(s?.topics?.map(\.state) == ["done", "active"])
    #expect(loadStatus(try tempFile("{bozuk")) == nil)
}
@Test func lastActionSurvivesLaterTextLine() throws {
    let t = readTranscriptTail(try tempFile("""
    {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"npm test"}}]}}
    {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Bitti."}]}}
    """))
    #expect(t.lastAction == "Bash · npm test")
}
@Test func registrySkipsMalformedFiles() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    func put(_ name: String, _ s: String) throws { try s.write(to: dir.appending(path: name), atomically: true, encoding: .utf8) }
    try put("13381.json", #"{"pid":13381,"sessionId":"d851","cwd":"/Users/o","startedAt":1,"kind":"interactive","name":"onur-4a","status":"idle","updatedAt":2,"statusUpdatedAt":1792721451546,"peerFeatures":["x"]}"#)
    try put("1.json", "{bozuk")
    try put("2.json", #"{"sessionId":"pid-yok"}"#)
    try put("13381.abc.key", "gizli")
    #expect(loadRegistry(dir: dir) == [RegistryEntry(pid: 13381, sessionId: "d851", cwd: "/Users/o", name: "onur-4a",
                                                     kind: "interactive", status: "idle", statusUpdatedAt: 1792721451546)])
    #expect(loadRegistry(dir: dir.appending(path: "yok")).isEmpty)
}
