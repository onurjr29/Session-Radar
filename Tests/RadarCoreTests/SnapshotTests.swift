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
    #expect(!isAlive(a, probe: { _ in 0 }) && !isAlive(nil))
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
                                 paths: radarPaths, now: Date(timeIntervalSince1970: now), probe: { live.contains($0) ? 0 : nil })
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
@Test func registryAfterClosedDialogEndsWaiting() {
    func st(_ a: Activity, _ status: String, at ms: Double) -> SessionState? {
        states(registry: [reg("s", pid: 7, status: status, at: ms)], activities: ["s": a], live: [7])["s"]
    }
    // izin penceresi Esc ya da ret ile kapandı: PostToolUse ve Stop gelmez, kayıt dosyası idle'a geçer
    var dialog = act(.waiting, at: 900); dialog.lastEvent = "Notification"; dialog.note = "izin"
    #expect(st(dialog, "idle", at: 950_000) == .turnDone)
    #expect(resolveState(activity: dialog, agent: nil, registry: reg("s", pid: 7, status: "idle", at: 950_000), alive: true,
                         seenAlive: true, status: nil) == (.turnDone, nil))
    // onaylandı, tool hâlâ sürüyor
    #expect(st(dialog, "busy", at: 950_000) == .working)
    // pencere açıkken kayıt dosyası "waiting" der
    #expect(st(dialog, "waiting", at: 950_000) == .waiting)
    // soru soran tur: idle Stop'tan hemen sonra yazılır, ~60 sn sonra idle_prompt gelir; bekleme sürer
    var question = act(.waiting, at: 900); question.lastEvent = "Stop"
    #expect(st(question, "idle", at: 900_030) == .waiting)
    question.lastEvent = "Notification"; question.lastEventAt = 960
    #expect(st(question, "idle", at: 900_030) == .waiting)
}
@Test func candidatesTakeLivenessFromRegistryThenAgents() {
    let agent = AgentEntry(id: nil, pid: 8, sessionId: "a", name: nil, cwd: "/r", kind: "interactive", startedAt: nil, status: "idle", state: nil)
    // aynı session'ın eski süreçten kalan kaydı canlı olanı gölgelemez
    let list = sessionCandidates(agents: [agent], registry: [reg("s", pid: 6), reg("s", pid: 7), reg("x", pid: 9)],
                                 activities: ["s": act(.working, at: 0)], seenAlive: [], paths: radarPaths,
                                 now: Date(timeIntervalSince1970: 1000), probe: { [7, 8].contains($0) ? 0 : nil })
    #expect(list.sorted { $0.id < $1.id }.map { "\($0.id):\($0.alive):\($0.seenAlive):\($0.registry?.pid ?? 0)" }
            == ["a:true:true:0", "s:true:true:7"])
}
@Test func reusedPidDoesNotKeepRegistryAlive() {
    // procStart `LC_ALL=C TZ=UTC ps -o lstart=` çıktısı; gün tek haneliyse boşlukla doldurulur
    #expect(parseProcStart("Sat Oct 17 23:31:27 2026") == 1792279887)
    #expect(parseProcStart("Fri Oct  2 01:02:03 2026") == 1790902923)
    #expect(parseProcStart("dün") == nil)
    var r = reg("s", pid: 7); r.procStart = "Sat Oct 17 23:31:27 2026"
    func alive(_ r: RegistryEntry, start: Double?) -> Bool? {
        sessionCandidates(agents: [], registry: [r], activities: ["s": act(.turnDone, at: 900)], seenAlive: [], paths: radarPaths,
                          now: Date(timeIntervalSince1970: 1000), probe: { _ in start }).first?.alive
    }
    #expect(alive(r, start: 1792279887.6) == true)
    #expect(alive(r, start: 1792290000) == false)   // kayıt dosyası eski sürecin, pid başkasına geçmiş
    #expect(alive(r, start: nil) == false)
    r.procStart = nil
    #expect(alive(r, start: 1792290000) == true)
}
@Test func sessionWithoutRegistryLivesWhileHookPidRuns() {
    // kayıt dosyası ve agents satırı yok (ör. claude -p); uzun tool çağrısında 100 sn olay gelmiyor
    var e = ev("PreToolUse", tool: "Bash", target: "sleep 300", ts: 900); e.pid = 5
    let a = reduceEvents([e])
    func alive(_ starts: [Int32: Double], registry: [RegistryEntry] = []) -> Bool? {
        sessionCandidates(agents: [], registry: registry, activities: ["h": a], seenAlive: [], paths: radarPaths,
                          now: Date(timeIntervalSince1970: 1000), probe: { starts[$0] }).first { $0.id == "h" }?.alive
    }
    #expect(alive([5: 800]) == true)
    #expect(alive([:]) == false)
    #expect(alive([5: 950]) == false)   // süreç son olaydan sonra başlamış: pid başkasına geçmiş
    // pid'in kayıt dosyası varsa o esas: aynı süreç /clear ya da /resume ile başka session'a geçmiş
    #expect(alive([5: 800], registry: [reg("other", pid: 5)]) == false)
}
@Test func processStartTimeReadsLiveProcess() throws {
    let start = try #require(processStartTime(getpid()))
    #expect(start <= Date().timeIntervalSince1970 && start > Date().timeIntervalSince1970 - 3600)
    #expect(processStartTime(Int32.max) == nil)
}
@Test func snapshotKeepsRepoRoot() {
    let s = buildSnapshot(SessionInputs(sessionId: "s", agent: nil, registry: nil, alive: true, seenAlive: true, activity: nil,
                                        status: nil, transcript: nil,
                                        repo: RepoInfo(toplevel: "/r", key: "k", name: "r", branch: "main", pending: []),
                                        lastSeen: Date(timeIntervalSince1970: 0)))
    #expect(s.repoRoot == "/r" && s.repoKey == "k")
}
