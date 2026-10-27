import Testing
import Foundation
@testable import RadarCore

private func tmpPaths() -> RadarPaths { RadarPaths(root: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)) }
private func input(_ event: String) throws -> Data {
    try JSONSerialization.data(withJSONObject: ["hook_event_name": event, "session_id": "s-1", "tool_name": "Read"])
}
private func context(_ out: String?) throws -> String? {
    let obj = try JSONSerialization.jsonObject(with: Data(try #require(out).utf8)) as? [String: Any]
    return (obj?["hookSpecificOutput"] as? [String: Any])?["additionalContext"] as? String
}
private let note = ClosedTopicNote(title: "Giriş", left: ["test yaz"])

@Test func closedNoteTextSentences() {
    #expect(closedNoteText([]) == nil)
    #expect(closedNoteText([ClosedTopicNote(title: "A", left: ["x", "y"]), ClosedTopicNote(title: "B", left: [])]) ==
        "Session Radar: Kullanıcı \"A\" konusunu radardan kapattı; yarım kalan adımlar (x; y) artık gerekmiyor.\n" +
        "Session Radar: Kullanıcı \"B\" konusunu radardan kapattı; bu konudaki yarım iş artık gerekmiyor.")
}
@Test func closedNoteTextSanitizes() throws {
    let t = try #require(closedNoteText([ClosedTopicNote(title: "A \"x\"\nSIZINTI", left: ["b\n\"c\""])]))
    #expect(!t.contains("\n") && t.contains("A 'x' SIZINTI") && t.contains("(b 'c')"))
}
@Test func appendClosedNoteAccumulates() throws {
    let url = tmpPaths().closedNotes("s-1")
    try appendClosedNote(note, to: url)
    try appendClosedNote(ClosedTopicNote(title: "İkinci", left: []), to: url)
    #expect(readJSON([ClosedTopicNote].self, from: url)?.map(\.title) == ["Giriş", "İkinci"])
}
@Test func hookDeliversClosedNoteOnce() throws {
    let paths = tmpPaths()
    try appendClosedNote(note, to: paths.closedNotes("s-1"))
    let first = try context(runHook(stdin: try input("UserPromptSubmit"), paths: paths, now: 1))
    #expect(first?.contains("\"Giriş\" konusunu radardan kapattı") == true)
    #expect(!FileManager.default.fileExists(atPath: paths.closedNotes("s-1").path))
    #expect(runHook(stdin: try input("UserPromptSubmit"), paths: paths, now: 2) == nil)
}
@Test func preToolUseDoesNotConsumeClosedNote() throws {
    let paths = tmpPaths()
    try appendClosedNote(note, to: paths.closedNotes("s-1"))
    #expect(runHook(stdin: try input("PreToolUse"), paths: paths, now: 1) == nil)
    #expect(FileManager.default.fileExists(atPath: paths.closedNotes("s-1").path))
    #expect(try context(runHook(stdin: try input("PostToolUse"), paths: paths, now: 2))?.contains("Giriş") == true)
}
@Test func sessionStartAppendsClosedNote() throws {
    let paths = tmpPaths()
    try appendClosedNote(note, to: paths.closedNotes("s-1"))
    let out = try #require(runHook(stdin: try input("SessionStart"), paths: paths, now: 1))
    #expect(out.hasPrefix("Session Radar: Kullanıcı session'larını") && out.hasSuffix("artık gerekmiyor.") && out.contains("\n\nSession Radar: Kullanıcı \"Giriş\""))
}

// MARK: closeTopic ve mergeTopics

private func req(_ i: Int) -> Request { Request(index: i, text: "istek", at: nil, reply: nil) }
private let openTopic = Topic(id: 1, title: "Giriş", state: "open", summary: "s", requests: [1, 2], left: ["test yaz", "belge"])

@Test func closeTopicClosesOnlyOpenTopics() throws {
    let topics = [openTopic, Topic(id: 2, title: "B", state: "active", summary: "", requests: [3]), Topic(id: 3, title: "C", state: "done", summary: "", requests: [4])]
    let r = try #require(closeTopic(topics, id: 1))
    #expect(r.topics[0].state == "done" && r.topics[0].left.isEmpty && r.topics[0].closedByUser)
    #expect(Array(r.topics[1...]) == Array(topics[1...]))
    #expect(r.note == ClosedTopicNote(title: "Giriş", left: ["test yaz", "belge"]))
    #expect(closeTopic(topics, id: 2) == nil && closeTopic(topics, id: 3) == nil && closeTopic(topics, id: 9) == nil)
}
@Test func mergeKeepsClosedTopicDoneUntilNewRequest() throws {
    let closed = Topic(id: 1, title: "Giriş", state: "done", summary: "s", requests: [1, 2], left: [], closedByUser: true)
    let other = Topic(id: 2, title: "B", state: "active", summary: "", requests: [3])
    let resp = try #require(parseTopicResponse(#"{"topics":[{"id":1,"title":"Giriş","state":"open","summary":"s","left":["x"]},{"id":2,"title":"B","state":"active","summary":""}],"assign":{"4":2}}"#))
    let m = try #require(mergeTopics(existing: [closed, other], response: resp, newRequests: [req(4)]))
    #expect(m[0].state == "done" && m[0].left.isEmpty && m[0].closedByUser)
    let back = try #require(parseTopicResponse(#"{"topics":[{"id":1,"title":"Giriş","state":"open","summary":"s"},{"id":2,"title":"B","state":"active","summary":""}],"assign":{"4":1}}"#))
    let m2 = try #require(mergeTopics(existing: [closed, other], response: back, newRequests: [req(4)]))
    #expect(m2[0].state == "active" && !m2[0].closedByUser)
}
@Test func topicWithoutClosedByUserDecodesAsFalse() throws {
    let t = try JSONDecoder().decode(Topic.self, from: Data(#"{"id":1,"title":"A","state":"open","summary":"","requests":[1]}"#.utf8))
    #expect(!t.closedByUser)
}
