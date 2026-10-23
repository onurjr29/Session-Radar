import Testing
import Foundation
@testable import RadarCore

private func req(_ i: Int, _ t: String = "istek") -> Request { Request(index: i, text: t, at: nil, reply: nil) }

@Test func parseResponseToleratesFencesAndProse() {
    let out = "İşte sonuç:\n```json\n{\"topics\":[{\"id\":1,\"title\":\"Giriş hatası\",\"state\":\"active\",\"summary\":\"Login düzeltildi.\"}],\"assign\":{\"1\":1}}\n```"
    #expect(parseTopicResponse(out)?.assign == ["1": 1])
}
@Test func parseResponseRejectsGarbage() {
    #expect(parseTopicResponse("Üzgünüm, yapamam.") == nil)
    #expect(parseTopicResponse("{\"topics\": 3}") == nil)
}
@Test func mergeAppendsNewRequestsAndTopics() throws {
    let existing = [Topic(id: 1, title: "Giriş", state: "active", summary: "s", requests: [1, 2])]
    let resp = try #require(parseTopicResponse(#"{"topics":[{"id":1,"title":"Giriş","state":"done","summary":"bitti"},{"id":2,"title":"Bildirim","state":"active","summary":"yeni"}],"assign":{"3":1,"4":2}}"#))
    let m = try #require(mergeTopics(existing: existing, response: resp, newRequests: [req(3), req(4)]))
    #expect(m.map(\.requests) == [[1, 2, 3], [4]] && m.map(\.state) == ["done", "active"])
}
@Test func mergeRejectsUnassignedOrUnknown() throws {
    let resp = try #require(parseTopicResponse(#"{"topics":[{"id":1,"title":"A","state":"active","summary":""}],"assign":{"3":1}}"#))
    #expect(mergeTopics(existing: [], response: resp, newRequests: [req(3), req(4)]) == nil)
    let bad = try #require(parseTopicResponse(#"{"topics":[{"id":1,"title":"A","state":"active","summary":""}],"assign":{"3":9}}"#))
    #expect(mergeTopics(existing: [], response: bad, newRequests: [req(3)]) == nil)
}
@Test func mergeNormalizesActive() throws {
    let resp = try #require(parseTopicResponse(#"{"topics":[{"id":1,"title":"A","state":"active","summary":""},{"id":2,"title":"B","state":"active","summary":""},{"id":3,"title":"C","state":"weird","summary":""}],"assign":{"1":1,"2":2,"3":3,"4":1}}"#))
    let m = try #require(mergeTopics(existing: [], response: resp, newRequests: [req(1), req(2), req(3), req(4)]))
    #expect(m.map(\.state) == ["active", "open", "open"])
}
@Test func chunkingRespectsBudget() {
    let long = (1...100).map { req($0, String(repeating: "x", count: 900)) }
    let chunks = chunkRequests(long, maxChars: 5_000)
    #expect(chunks.flatMap { $0 }.map(\.index) == Array(1...100))
    #expect(chunks.allSatisfy { $0.count * 540 <= 5_000 || $0.count == 1 })   // her istek 500 + 0 + 40
}
@Test func promptCarriesSchemaAndTruncates() {
    let p = buildTopicPrompt(existing: [], requests: [Request(index: 7, text: String(repeating: "a", count: 900), at: nil, reply: String(repeating: "b", count: 900))])
    #expect(p.contains("\"assign\"") && p.contains("#7") && !p.contains(String(repeating: "a", count: 501)) && !p.contains(String(repeating: "b", count: 301)))
}
@Test func promptListsRealRequestNumbersOfInterleavedTopics() {
    let existing = [Topic(id: 1, title: "A", state: "open", summary: "", requests: [1, 2] + Array(13...20)),
                    Topic(id: 2, title: "B", state: "active", summary: "", requests: [3, 4, 5, 6, 12, 21])]
    let p = buildTopicPrompt(existing: existing, requests: [req(22)])
    #expect(p.contains("istekler: #1,#2,#13-#20 |") && p.contains("istekler: #3-#6,#12,#21 |"))
}
@Test func topicFileRoundTripsWithPrivatePermissions() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".json")
    let f = TopicFile(sessionId: "s", grouped: 2, topics: [Topic(id: 1, title: "A", state: "active", summary: "", requests: [1, 2])], updatedAt: Date(timeIntervalSince1970: 1))
    try saveTopicFile(f, to: url)
    #expect(loadTopicFile(url) == f)
    #expect((try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int) == 0o600)
}
@Test func topicFileWithOtherVersionIsIgnored() throws {
    let dir = FileManager.default.temporaryDirectory
    func load(_ version: String) throws -> TopicFile? {
        let url = dir.appending(path: UUID().uuidString + ".json")
        try #"{\#(version)"sessionId":"s","grouped":1,"topics":[],"updatedAt":"1970-01-01T00:00:01Z"}"#.write(to: url, atomically: true, encoding: .utf8)
        return loadTopicFile(url)
    }
    #expect(try load("") == nil)
    #expect(try load(#""version":1,"#) == nil)
    #expect(try load(#""version":2,"#)?.grouped == 1)
}

func cand(_ id: String, _ n: Int, _ st: SessionState = .turnDone, alive: Bool = true, last: Date? = nil, backlog: Bool = false, failures: Int = 0) -> GroupingCandidate {
    GroupingCandidate(id: id, ungrouped: n, state: st, alive: alive, lastRunAt: last, lastRunLeftBacklog: backlog, failures: failures)
}
@Test func schedulerRules() {
    let now = Date(timeIntervalSince1970: 1_000)
    #expect(nextGroupingJob([cand("a", 0), cand("b", 3)], selected: nil, now: now) == "b")
    #expect(nextGroupingJob([cand("a", 3, .working)], selected: nil, now: now) == nil)
    #expect(nextGroupingJob([cand("a", 3, .working)], selected: "a", now: now) == "a")
    #expect(nextGroupingJob([cand("a", 3, .closed, alive: false)], selected: nil, now: now) == nil)
    #expect(nextGroupingJob([cand("a", 3, last: now.addingTimeInterval(-60))], selected: nil, now: now) == nil)
    #expect(nextGroupingJob([cand("a", 3, last: now.addingTimeInterval(-60), backlog: true)], selected: nil, now: now) == "a")
    #expect(nextGroupingJob([cand("a", 3), cand("b", 3)], selected: "b", now: now) == "b")
}
@Test func schedulerBacksOffAfterFailures() {
    let now = Date(timeIntervalSince1970: 10_000)
    func job(ago: TimeInterval, failures: Int, backlog: Bool = false) -> String? {
        nextGroupingJob([cand("a", 3, last: now.addingTimeInterval(-ago), backlog: backlog, failures: failures)], selected: nil, now: now)
    }
    #expect(job(ago: 119, failures: 0) == nil && job(ago: 120, failures: 0) == "a")
    #expect(job(ago: 300, failures: 2) == nil && job(ago: 500, failures: 2) == "a")
    #expect(job(ago: 3599, failures: 10) == nil && job(ago: 3600, failures: 10) == "a")
    #expect(job(ago: 60, failures: 1, backlog: true) == nil)
}
@Test func labelsFollowSessionState() {
    #expect(topicStateLabel("active", sessionClosed: false) == "Şu anki")
    #expect(topicStateLabel("active", sessionClosed: true) == "Son konu")
    #expect(topicStateLabel("open", sessionClosed: false) == "Açık kaldı")
    #expect(topicStateLabel("done", sessionClosed: false) == "Kapandı")
    #expect(topicStateLabel("x", sessionClosed: false) == "Açık kaldı")
}
@Test func snapshotUsesTopicsThenLastPrompt() {
    let topics = [Topic(id: 1, title: "Eski", state: "open", summary: "", requests: [1]), Topic(id: 2, title: "Bildirimler", state: "active", summary: "", requests: [2])]
    func inputs(_ t: [Topic]) -> SessionInputs {
        SessionInputs(sessionId: "s", agent: nil, registry: nil, alive: true, seenAlive: true, activity: nil, status: nil,
                      transcript: TranscriptInfo(aiTitle: nil, lastPrompt: "Son istek", lastAction: nil, dialogue: []),
                      repo: nil, lastSeen: Date(), topics: t)
    }
    let a = buildSnapshot(inputs(topics))
    #expect(a.currentTopic == "Bildirimler" && a.openTopics == 1)
    let b = buildSnapshot(inputs([]))
    #expect(b.currentTopic == "Son istek" && b.openTopics == 0)
}
@Test func startContextHasNoTopics() {
    #expect(!sessionStartContext(statusFile: URL(fileURLWithPath: "/x/s.json")).contains("topics"))
}
