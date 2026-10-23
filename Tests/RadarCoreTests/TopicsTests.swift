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
@Test func topicFileRoundTripsWithPrivatePermissions() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".json")
    let f = TopicFile(sessionId: "s", grouped: 2, topics: [Topic(id: 1, title: "A", state: "active", summary: "", requests: [1, 2])], updatedAt: Date(timeIntervalSince1970: 1))
    try saveTopicFile(f, to: url)
    #expect(loadTopicFile(url) == f)
    #expect((try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int) == 0o600)
}
