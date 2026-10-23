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
    let s = buildSnapshot(SessionInputs(sessionId: "s", agent: nil, registry: nil, alive: true, seenAlive: true, activity: nil, status: nil,
        transcript: TranscriptInfo(aiTitle: "Başlık", lastPrompt: String(repeating: "a", count: 100) + "\nikinci", lastAction: "Edit · x.swift", dialogue: []),
        repo: nil, lastSeen: Date(timeIntervalSince1970: 5)))
    #expect(s.name == "Başlık" && s.task == String(repeating: "a", count: 80) + "…" && s.updatedAt.timeIntervalSince1970 == 5)
}
@Test func badgeAndOrder() {
    let list = [snap("w", .working), snap("c", .closed), snap("q", .waiting), snap("p", .problem)]
    #expect(badgeCount(list) == 2 && sortForDisplay(list).map(\.id) == ["q", "p", "w", "c"])
}

private let radarPaths = RadarPaths(root: URL(fileURLWithPath: "/tmp/radar-test"))
private func act(_ st: SessionState, at t: Double) -> Activity {
    var a = Activity(); a.state = st; a.lastEventAt = t; a.cwd = "/r"; return a
}
private func reg(_ sid: String, pid: Int32, status: String? = nil, at ms: Double? = nil) -> RegistryEntry {
    RegistryEntry(pid: pid, sessionId: sid, cwd: "/r", name: nil, kind: "interactive", status: status, statusUpdatedAt: ms)
}
/// aday seçimi + anlık görüntü zincirinden çıkan durumlar; `live` canlı pid'ler
private func states(agents: [AgentEntry] = [], registry: [RegistryEntry] = [], activities: [String: Activity],
                    seen: Set<String> = [], live: Set<Int32> = [], now: Double = 1000) -> [String: SessionState] {
    let list = sessionCandidates(agents: agents, registry: registry, activities: activities, seenAlive: seen,
                                 paths: radarPaths, now: Date(timeIntervalSince1970: now), probe: { live.contains($0) })
    return Dictionary(uniqueKeysWithValues: list.map { c in
        (c.id, buildSnapshot(SessionInputs(sessionId: c.id, agent: c.agent, registry: c.registry, alive: c.alive,
                                           seenAlive: c.seenAlive, activity: c.activity, status: nil, transcript: nil,
                                           repo: nil, lastSeen: Date(timeIntervalSince1970: now))).state)
    })
}

@Test func newSessionWithOnlyEventsIsNotProblem() {
    // kayıt dosyası ve agents henüz yok: taze olay canlı sayılır; hiç canlı görülmediyse sonra kapandı olur
    #expect(states(activities: ["n": act(.working, at: 995)]) == ["n": .working])
    #expect(states(activities: ["n": act(.working, at: 900)]) == ["n": .closed])
}
@Test func clearedSessionIsNotProblem() {
    var old = act(.turnDone, at: 990); old.ended = true
    let base = ["old": old]
    #expect(states(registry: [reg("old", pid: 7)], activities: base.merging(["new": act(.working, at: 995)]) { $1 },
                   seen: ["old"], live: [7]) == ["old": .closed, "new": .working])
    #expect(states(registry: [reg("old", pid: 7)], activities: base.merging(["new": act(.working, at: 900)]) { $1 },
                   seen: ["old"], live: [7]) == ["old": .closed, "new": .closed])
}
@Test func sessionSeenAliveThenGoneWhileWorkingIsProblem() {
    let acts = ["s": act(.working, at: 900)]
    #expect(states(registry: [reg("s", pid: 7)], activities: acts, live: [7]) == ["s": .working])
    #expect(states(registry: [reg("s", pid: 7)], activities: acts, seen: ["s"]) == ["s": .problem])
}
@Test func neverSeenAliveAndGoneIsClosed() {
    #expect(states(registry: [reg("s", pid: 7)], activities: ["s": act(.working, at: 900)]) == ["s": .closed])
}
@Test func registryIdleAfterLastEventEndsTurn() {
    let acts = ["s": act(.working, at: 900)]
    #expect(states(registry: [reg("s", pid: 7, status: "idle", at: 950_000)], activities: acts, live: [7]) == ["s": .turnDone])
    #expect(states(registry: [reg("s", pid: 7, status: "idle", at: 850_000)], activities: acts, live: [7]) == ["s": .working])
    #expect(states(registry: [reg("s", pid: 7, status: "busy", at: 950_000)], activities: acts, live: [7]) == ["s": .working])
    // Stop arka plan işi yüzünden working bıraktıysa tur kesilmemiştir
    var bg = act(.working, at: 900); bg.lastEvent = "Stop"
    #expect(states(registry: [reg("s", pid: 7, status: "idle", at: 950_000)], activities: ["s": bg], live: [7]) == ["s": .working])
}
@Test func candidatesTakeLivenessFromRegistryThenAgents() {
    let agent = AgentEntry(id: nil, pid: 8, sessionId: "a", name: nil, cwd: "/r", kind: "interactive", startedAt: nil, status: "idle", state: nil)
    // aynı session'ın eski süreçten kalan kaydı canlı olanı gölgelemez
    let list = sessionCandidates(agents: [agent], registry: [reg("s", pid: 6), reg("s", pid: 7), reg("x", pid: 9)],
                                 activities: ["s": act(.working, at: 0)], seenAlive: [], paths: radarPaths,
                                 now: Date(timeIntervalSince1970: 1000), probe: { [7, 8].contains($0) })
    #expect(list.sorted { $0.id < $1.id }.map { "\($0.id):\($0.alive):\($0.seenAlive):\($0.registry?.pid ?? 0)" }
            == ["a:true:true:0", "s:true:true:7"])
}
@Test func snapshotKeepsRepoRoot() {
    let s = buildSnapshot(SessionInputs(sessionId: "s", agent: nil, registry: nil, alive: true, seenAlive: true, activity: nil,
                                        status: nil, transcript: nil,
                                        repo: RepoInfo(toplevel: "/r", key: "k", name: "r", branch: "main", pending: []),
                                        lastSeen: Date(timeIntervalSince1970: 0)))
    #expect(s.repoRoot == "/r" && s.repoKey == "k")
}
