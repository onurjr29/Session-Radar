import Testing
import Foundation
@testable import RadarCore

private let repo = "github.com/x/y"
private let now = Date(timeIntervalSince1970: 1_800_000_000)
private let t10 = now.addingTimeInterval(-3600)

private func claimSnap(_ id: String = "S", alive: Bool = true, repoKey: String? = repo, status: SessionStatus? = nil,
                       statusAt: Date? = nil, state: SessionState = .working) -> SessionSnapshot {
    SessionSnapshot(id: id, name: id, cwd: "", repoName: nil, repoKey: repoKey, branch: "main", state: state, note: nil,
                    task: "gizli prompt metni", action: nil, progress: nil, status: status, pendingFiles: [],
                    transcriptPath: nil, updatedAt: now, currentTopic: "gizli prompt metni", alive: alive, statusUpdatedAt: statusAt)
}

private func claimHistory(last: Date = t10, topics: [Topic] = []) -> SessionHistory {
    SessionHistory(requests: [Request(index: 1, text: "x", at: last, reply: nil)], topics: topics, grouping: false)
}

private func topic(_ id: Int, _ title: String, _ state: String) -> Topic {
    Topic(id: id, title: title, state: state, summary: "", requests: [])
}

@Test func claimUsesFreshStatusTaskOverTopic() {
    let s = claimSnap(status: SessionStatus(task: "Durum görevi"), statusAt: t10.addingTimeInterval(300))
    let c = buildClaims([s], histories: [s.id: claimHistory(topics: [topic(1, "Konu", "active")])],
                        owner: "Onur", shared: [repo], now: now)
    #expect(c.first?.topic == "Durum görevi")
}

@Test func claimFallsBackToActiveTopicWhenStatusStale() {
    let s = claimSnap(status: SessionStatus(task: "Eski"), statusAt: t10.addingTimeInterval(-3600))
    let c = buildClaims([s], histories: [s.id: claimHistory(topics: [topic(1, "Konu", "active")])],
                        owner: "Onur", shared: [repo], now: now)
    #expect(c.first?.topic == "Konu")
}

@Test func noClaimWithoutStatusOrTopic() {
    let s = claimSnap()
    #expect(buildClaims([s], histories: [s.id: claimHistory()], owner: "Onur", shared: [repo], now: now).isEmpty)
}

@Test func noClaimForUnsharedDeadOrOldSessions() {
    let h = claimHistory(topics: [topic(1, "Konu", "active")])
    func run(_ s: SessionSnapshot, _ h: SessionHistory, shared: Set<String> = [repo]) -> Int {
        buildClaims([s], histories: [s.id: h], owner: "Onur", shared: shared, now: now).count
    }
    #expect(run(claimSnap(), h, shared: []) == 0)
    #expect(run(claimSnap(alive: false), h) == 0)
    #expect(run(claimSnap(), claimHistory(last: now.addingTimeInterval(-claimMaxAge - 1), topics: h.topics)) == 0)
    #expect(run(claimSnap(), claimHistory(last: now.addingTimeInterval(-claimMaxAge + 1), topics: h.topics)) == 1)
}

@Test func claimTextIsSanitized() {
    let opens = (1...7).map { topic($0, "açık \($0)", "open") }
    let s = claimSnap()
    let c = buildClaims([s], histories: [s.id: claimHistory(topics: [topic(0, "a\"b\nc" + String(repeating: "x", count: 200), "active")] + opens)],
                        owner: String(repeating: "o", count: 60), shared: [repo], now: now)[0]
    #expect(c.topic.hasPrefix("a'b c") && c.topic.count <= 80 && !c.topic.contains("\n"))
    #expect(c.ownerName.count <= 40)
    #expect(c.openTopics.count == 5)
}

@Test func claimLengthsCountCodePoints() throws {
    let emoji = String(repeating: "👍🏽", count: 100)   // 100 grapheme, 200 code point
    #expect(teamText(emoji, max: 80) == String(repeating: "👍🏽", count: 40))
    let long = "github.com/" + String(repeating: "e\u{301}", count: 150)   // 161 grapheme, 311 code point
    var s = claimSnap(repoKey: long)
    s.branch = long
    let c = try #require(buildClaims([s], histories: [s.id: claimHistory(topics: [topic(1, emoji, "active")])],
                                     owner: "Onur", shared: [long], now: now).first)
    #expect(c.topic.unicodeScalars.count <= 80)
    #expect(c.repoKey.unicodeScalars.count <= 200)
    #expect((c.branch?.unicodeScalars.count ?? 999) <= 200)
}

@Test func teamClaimEncodesSnakeCase() throws {
    let c = TeamClaim(ownerId: nil, ownerName: "O", sessionId: "S", repoKey: "r", branch: nil, topic: "t",
                      openTopics: [], working: true, lastRequestAt: now, updatedAt: nil)
    let json = String(decoding: try JSONEncoder().encode(c), as: UTF8.self)
    for k in ["session_id", "repo_key", "open_topics", "last_request_at", "owner_name"] { #expect(json.contains(k)) }
}
