import Testing
import Foundation
@testable import RadarCore

@Test func preToolUseWriteKeepsOnlyPath() throws {
    let e = try #require(makeHookEvent(from: ["hook_event_name": "PreToolUse", "session_id": "s-1",
        "tool_name": "Write", "tool_input": ["file_path": "/r/a.swift", "content": "SECRET"]], now: 1))
    #expect(e.target == "/r/a.swift")
    #expect(!String(decoding: try JSONEncoder().encode(e), as: UTF8.self).contains("SECRET"))
}
@Test func bashCommandIsFirstLineCappedAt120() throws {
    let cmd = String(repeating: "x", count: 300) + "\nsecond"
    let e = try #require(makeHookEvent(from: ["hook_event_name": "PreToolUse", "session_id": "s-1",
        "tool_name": "Bash", "tool_input": ["command": cmd]], now: 1))
    #expect(e.target == String(repeating: "x", count: 120))
}
@Test func stopCapturesQuestionAndBackgroundTasks() throws {
    let e = try #require(makeHookEvent(from: ["hook_event_name": "Stop", "session_id": "s-1",
        "last_assistant_message": "Tamam.\n\nOnaylıyor musun?", "background_tasks": [["id": "b1"]]], now: 1))
    #expect(e.endsWithQuestion == true && e.backgroundTasks == 1 && e.message == "Tamam.\n\nOnaylıyor musun?")
    #expect(endsWithQuestion("Bitti.") == false)
    #expect(endsWithQuestion("Soru?\n\nTamamlandı.") == false)
}
@Test func invalidSessionIdRejected() {
    #expect(makeHookEvent(from: ["hook_event_name": "Stop", "session_id": "../x"], now: 1) == nil)
}
@Test func runHookAppendsAndReturnsContextOnlyOnSessionStart() throws {
    let paths = RadarPaths(root: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
    let start = try JSONSerialization.data(withJSONObject: ["hook_event_name": "SessionStart", "session_id": "s-1", "cwd": "/r"])
    let ctx = try #require(runHook(stdin: start, paths: paths, now: 1))
    #expect(ctx.contains(paths.statusFile("s-1").path))
    let tool = try JSONSerialization.data(withJSONObject: ["hook_event_name": "PreToolUse", "session_id": "s-1", "tool_name": "Read"])
    #expect(runHook(stdin: tool, paths: paths, now: 2) == nil)
    let lines = try String(contentsOf: paths.eventLog("s-1"), encoding: .utf8).split(separator: "\n")
    #expect(lines.count == 2)
}
@Test func runHookIgnoresMalformedInput() {
    let paths = RadarPaths(root: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
    #expect(runHook(stdin: Data("not json".utf8), paths: paths, now: 1) == nil)
    #expect(!FileManager.default.fileExists(atPath: paths.eventsDir.path))
}
