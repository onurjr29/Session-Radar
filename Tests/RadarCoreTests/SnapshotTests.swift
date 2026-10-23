import Testing
import Foundation
@testable import RadarCore

func snap(_ id: String, _ st: SessionState, note: String? = nil, task: String? = nil) -> SessionSnapshot {
    SessionSnapshot(id: id, name: id, cwd: "", repoName: nil, repoKey: nil, branch: nil, state: st, note: note,
                    task: task, action: nil, progress: nil, status: nil, pendingFiles: [], transcriptPath: nil,
                    updatedAt: Date(timeIntervalSince1970: 0))
}

@Test func seedProducesNothing() {
    #expect(transitions(previous: nil, previousConflictPairs: [], current: [snap("A", .waiting)], conflicts: []).isEmpty)
}
@Test func notifiesOnMeaningfulTransitions() {
    let n = transitions(previous: ["A": .working, "B": .turnDone, "C": .waiting, "D": .working],
                        previousConflictPairs: [],
                        current: [snap("A", .turnDone, task: "Login"), snap("B", .waiting, note: "Onay?"),
                                  snap("C", .waiting), snap("D", .problem, note: "build kırık"), snap("E", .waiting)],
                        conflicts: [])
    #expect(n.map(\.title) == ["A işini bitirdi", "B seni bekliyor", "D: sorun var", "E seni bekliyor"])
    #expect(n[1].body == "Onay?")
}
@Test func conflictNotifiedOncePerPair() {
    let c = Conflict(a: "A", b: "B", files: ["x", "y", "z", "w"])
    let first = transitions(previous: [:], previousConflictPairs: [], current: [snap("A", .working), snap("B", .working)], conflicts: [c])
    #expect(first.map(\.body) == ["x, y, z +1"])
    #expect(transitions(previous: [:], previousConflictPairs: [c.pairKey], current: [], conflicts: [c]).isEmpty)
}
@Test func isAliveFalseWithoutPid() {
    let a = AgentEntry(id: "x", pid: nil, sessionId: "s", name: nil, cwd: "/r", kind: "background", startedAt: nil, status: nil, state: "blocked")
    #expect(!isAlive(a, probe: { _ in true }) && !isAlive(nil))
}
@Test func snapshotFallsBackToTranscript() {
    let s = buildSnapshot(SessionInputs(sessionId: "s", agent: nil, alive: true, activity: nil, status: nil,
        transcript: TranscriptInfo(aiTitle: "Başlık", lastPrompt: String(repeating: "a", count: 100) + "\nikinci", lastAction: "Edit · x.swift", dialogue: []),
        repo: nil, lastSeen: Date(timeIntervalSince1970: 5)))
    #expect(s.name == "Başlık" && s.task == String(repeating: "a", count: 80) + "…" && s.updatedAt.timeIntervalSince1970 == 5)
}
@Test func topicSummaryCountsOpen() {
    let t = [TopicItem(title: "A", state: "done"), TopicItem(title: "B", state: "open"), TopicItem(title: "C", state: "active")]
    let s = topicSummary(t)
    #expect(s.current == "C" && s.open == 1)
    #expect(topicSummary(nil).current == nil && topicSummary(nil).open == 0)
}
@Test func badgeAndOrder() {
    let list = [snap("w", .working), snap("c", .closed), snap("q", .waiting), snap("p", .problem)]
    #expect(badgeCount(list) == 2 && sortForDisplay(list).map(\.id) == ["q", "p", "w", "c"])
}
