import Testing
import Foundation
@testable import RadarCore

func jsonString(_ s: String) -> String {
    String(decoding: (try? JSONEncoder().encode(s)) ?? Data("\"\"".utf8), as: UTF8.self)
}
func userLine(_ text: String, ts: String = "2026-10-23T01:11:49.379Z", extra: String = "") -> String {
    #"{"type":"user",\#(extra)"timestamp":"\#(ts)","message":{"role":"user","content":\#(jsonString(text))}}"#
}
func assistantText(_ text: String) -> String {
    #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":\#(jsonString(text))}]}}"#
}
@Test func requestFilterMatchesRealNoise() throws {
    let lines = [
        userLine("Login hatasını düzelt"),
        userLine("<task-notification>\n<task-id>x</task-id>"),
        userLine("<command-name>/clear</command-name>"),
        userLine("<local-command-stdout></local-command-stdout>"),
        userLine("<bash-input>ls</bash-input>"),
        userLine("This session is being continued from a previous conversation", extra: #""isCompactSummary":true,"#),
        userLine("meta", extra: #""isMeta":true,"#),
        userLine("alt görev", extra: #""isSidechain":true,"#),
        userLine("[Request interrupted by user]"),
        userLine("<pasted_content id=\"a\">log</pasted_content>"),
        #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"ok"}]}}"#,
    ]
    let r = readRequests(try tempFile(lines.joined(separator: "\n") + "\n"), from: HistoryCursor())
    #expect(r.requests.map(\.text) == ["Login hatasını düzelt", "<pasted_content id=\"a\">log</pasted_content>"])
    #expect(r.requests.map(\.index) == [1, 2])
    #expect(r.requests[0].at != nil)
}
@Test func replyIsLastAssistantTextOfTurn() throws {
    let r = readRequests(try tempFile([userLine("A"), assistantText("ilk"), assistantText("son"), userLine("B"), assistantText("B cevap")].joined(separator: "\n") + "\n"), from: HistoryCursor())
    #expect(r.requests.map(\.reply) == ["son", "B cevap"])
}
@Test func readRequestsStopsAtPartialLine() throws {
    let url = try tempFile(userLine("A") + "\n" + String(userLine("B").prefix(20)))
    let r = readRequests(url, from: HistoryCursor())
    #expect(r.requests.map(\.text) == ["A"] && r.cursor.nextIndex == 2)
}
@Test func readRequestsContinuesIndexAcrossReads() throws {
    let url = try tempFile(userLine("A") + "\n")
    let first = readRequests(url, from: HistoryCursor(), chunkSize: 64)
    let h = try FileHandle(forWritingTo: url); try h.seekToEnd()
    try h.write(contentsOf: Data((assistantText("A cevap") + "\n" + userLine("B") + "\n").utf8)); try h.close()
    let second = readRequests(url, from: first.cursor, chunkSize: 64)
    #expect(second.requests.map(\.index) == [2] && second.trailingReply == "A cevap")
}
@Test func readRequestsDetectsTruncation() throws {
    let url = try tempFile(userLine("A") + "\n" + userLine("B") + "\n")
    let first = readRequests(url, from: HistoryCursor())
    try (userLine("Yeni") + "\n").write(to: url, atomically: true, encoding: .utf8)
    let again = readRequests(url, from: first.cursor)
    #expect(again.truncated && again.requests.map(\.index) == [1] && again.requests[0].text == "Yeni")
}
@Test(.enabled(if: ProcessInfo.processInfo.environment["RADAR_BIG_TRANSCRIPT"] != nil)) func bigTranscriptSmoke() {
    let url = URL(fileURLWithPath: ProcessInfo.processInfo.environment["RADAR_BIG_TRANSCRIPT"] ?? "")
    let t0 = Date()
    let r = readRequests(url, from: HistoryCursor())
    print("SMOKE requests=\(r.requests.count) seconds=\(Date().timeIntervalSince(t0))")
    #expect(r.requests.count > 0)
}
@Test func imageRequestsCountWithTheirText() throws {
    func arrayLine(_ blocks: String) -> String {
        #"{"type":"user","timestamp":"2026-10-23T01:11:49.379Z","message":{"role":"user","content":[\#(blocks)]}}"#
    }
    let lines = [
        arrayLine(#"{"type":"image","source":{"type":"base64","media_type":"image/png","data":"AAAA"}},{"type":"text","text":"[Image #1] Bu ekrandaki gri karaltı"}"#),
        arrayLine(#"{"type":"tool_result","content":"ok"},{"type":"text","text":"araç çıktısı"}"#),
        arrayLine(#"{"type":"text","text":"[Request interrupted by user]"}"#),
    ]
    let r = readRequests(try tempFile(lines.joined(separator: "\n") + "\n"), from: HistoryCursor())
    #expect(r.requests.map(\.text) == ["[Image #1] Bu ekrandaki gri karaltı"])
}
@Test func bareSlashCommandsAreNotRequests() throws {
    let lines = ["/compact", "  /usage\n", "/plugin:skill", "/Users/x/a.swift neden bozuk", "/review bu PR'ı incele"].map { userLine($0) }
    let r = readRequests(try tempFile(lines.joined(separator: "\n") + "\n"), from: HistoryCursor())
    #expect(r.requests.map(\.text) == ["/Users/x/a.swift neden bozuk", "/review bu PR'ı incele"])
}
