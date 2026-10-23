import Testing
import Foundation
@testable import RadarCore

func ev(_ name: String, tool: String? = nil, target: String? = nil, nt: String? = nil, msg: String? = nil,
        q: Bool? = nil, bg: Int? = nil, src: String? = nil, ts: Double = 1) -> HookEvent {
    HookEvent(ts: ts, event: name, sessionId: "s", cwd: nil, transcriptPath: nil, tool: tool, target: target,
              notificationType: nt, message: msg, endsWithQuestion: q, backgroundTasks: bg, source: src)
}
@Test func reduceFollowsTurnLifecycle() {
    var a = reduceEvents([ev("SessionStart"), ev("UserPromptSubmit"), ev("PreToolUse", tool: "Edit", target: "/r/a.swift")])
    #expect(a.state == .working && a.action == "Edit · a.swift")
    apply(ev("PostToolUse", tool: "Edit", target: "/r/a.swift"), to: &a);  #expect(a.touched == ["/r/a.swift"])
    apply(ev("Stop", msg: "Devam edeyim mi?", q: true), to: &a);          #expect(a.state == .waiting && a.note == "Devam edeyim mi?")
    apply(ev("UserPromptSubmit"), to: &a);                                #expect(a.state == .working && a.note == nil)
    apply(ev("Notification", nt: "permission_prompt", msg: "izin"), to: &a); #expect(a.state == .waiting)
    apply(ev("PostToolUse", tool: "Bash", target: "ls"), to: &a);         #expect(a.state == .working)
    apply(ev("Stop", bg: 1), to: &a);                                     #expect(a.state == .working)
    apply(ev("Stop", q: false), to: &a);                                  #expect(a.state == .turnDone && a.action == nil)
    apply(ev("StopFailure", msg: "rate_limit"), to: &a);                  #expect(a.state == .problem && a.note == "API hatası: rate_limit")
    apply(ev("SessionEnd"), to: &a);                                      #expect(a.ended && a.state == .closed)
}
@Test func radarOwnFilesAreIgnored() {
    let a = reduceEvents([ev("Stop", q: false), ev("PreToolUse", tool: "Write", target: "/Users/o/.session-radar/status/s.json")])
    #expect(a.state == .turnDone && a.action == nil)
}
@Test func resolveRules() {
    var working = Activity(); working.state = .working
    var ended = Activity(); ended.ended = true
    #expect(resolveState(activity: ended, agent: nil, registry: nil, alive: true, seenAlive: true, status: nil).state == .closed)
    #expect(resolveState(activity: working, agent: nil, registry: nil, alive: false, seenAlive: true, status: nil) == (.problem, "Session beklenmedik şekilde kapandı"))
    #expect(resolveState(activity: Activity(), agent: nil, registry: nil, alive: false, seenAlive: true, status: nil).state == .closed)
    #expect(resolveState(activity: working, agent: nil, registry: nil, alive: true, seenAlive: true, status: SessionStatus(problems: ["build kırık"])) == (.problem, "build kırık"))
}
@Test func resolveFallsBackToAgentWithoutEvents() {
    let bg = AgentEntry(id: "x", pid: 1, sessionId: "s", name: nil, cwd: "/r", kind: "background", startedAt: nil, status: nil, state: "blocked")
    let it = AgentEntry(id: nil, pid: 2, sessionId: "s", name: nil, cwd: "/r", kind: "interactive", startedAt: nil, status: "busy", state: nil)
    #expect(resolveState(activity: nil, agent: bg, registry: nil, alive: true, seenAlive: true, status: nil).state == .waiting)
    #expect(resolveState(activity: nil, agent: it, registry: nil, alive: true, seenAlive: true, status: nil).state == .working)
}
@Test func resolveWithoutEventsTrustsProcessStatus() {
    func bg(_ status: String?, _ state: String?) -> AgentEntry {
        AgentEntry(id: "x", pid: 1, sessionId: "s", name: nil, cwd: "/r", kind: "background", startedAt: nil, status: status, state: state)
    }
    func st(_ a: AgentEntry?, _ status: String? = nil) -> SessionState {
        let r = RegistryEntry(pid: 1, sessionId: "s", cwd: "/r", name: nil, kind: "bg", status: status, statusUpdatedAt: 1)
        return resolveState(activity: nil, agent: a, registry: r, alive: true, seenAlive: true, status: nil).state
    }
    // agents'taki state işin son mesajından çıkar; süreç günlerdir boştayken de "working" kalabilir
    #expect(st(bg("idle", "working")) == .turnDone)
    #expect(st(bg("busy", "working")) == .working)
    #expect(st(bg("idle", "blocked")) == .waiting)
    #expect(st(bg("busy", "blocked")) == .working)
    // agents satırı yoksa kayıt dosyası
    #expect(st(nil, "busy") == .working)
    #expect(st(nil, "waiting") == .waiting)
    #expect(st(nil, "idle") == .turnDone)
}
@Test func resolveStoppedBackgroundIsClosed() {
    let stopped = AgentEntry(id: "x", pid: nil, sessionId: "s", name: nil, cwd: "/r", kind: "background", startedAt: nil, status: nil, state: "blocked")
    #expect(resolveState(activity: nil, agent: stopped, registry: nil, alive: false, seenAlive: true, status: nil).state == .closed)
}
@Test func readerWaitsForCompleteLine() throws {
    let paths = RadarPaths(root: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
    let line = String(decoding: try JSONEncoder().encode(ev("Stop")), as: UTF8.self)
    try appendLine(Data((line + "\n").utf8), to: paths.eventLog("s"))
    let h = try FileHandle(forWritingTo: paths.eventLog("s")); try h.seekToEnd()
    try h.write(contentsOf: Data(line.prefix(10).utf8))
    let r = EventLogReader(paths: paths)
    #expect(r.poll()["s"]?.count == 1)
    try h.write(contentsOf: Data((line.dropFirst(10) + "\nnot json\n").utf8)); try h.close()
    #expect(r.poll()["s"]?.count == 1)
    #expect(r.poll().isEmpty)
}
@Test func resumedSessionIsNotClosed() {
    let a = reduceEvents([ev("SessionStart", src: "startup"), ev("SessionEnd"), ev("SessionStart", src: "resume"),
                          ev("UserPromptSubmit"), ev("Notification", nt: "permission_prompt", msg: "izin")])
    #expect(!a.ended)
    #expect(resolveState(activity: a, agent: nil, registry: nil, alive: true, seenAlive: true, status: nil) == (.waiting, "izin"))
}
@Test func compactionKeepsState() {
    var waiting = reduceEvents([ev("UserPromptSubmit"), ev("Notification", nt: "permission_prompt", msg: "izin")])
    apply(ev("SessionStart", src: "compact", ts: 5), to: &waiting)
    #expect(waiting.state == .waiting && waiting.note == "izin" && waiting.lastEventAt == 5)
    var working = reduceEvents([ev("UserPromptSubmit"), ev("PreToolUse", tool: "Edit", target: "/r/a.swift"),
                                ev("PostToolUse", tool: "Edit", target: "/r/a.swift")])
    apply(ev("SessionStart", src: "compact"), to: &working)
    #expect(working.state == .working && working.action == "Edit · a.swift" && working.touched == ["/r/a.swift"])
    var done = reduceEvents([ev("UserPromptSubmit"), ev("PreToolUse", tool: "Bash", target: "ls"), ev("Stop", msg: "Soru?", q: true)])
    apply(ev("SessionStart", src: "startup"), to: &done)
    #expect(done.state == .turnDone && done.action == nil && done.note == nil)
}
@Test func waitingWinsOverStatusProblems() {
    var waiting = Activity(); waiting.state = .waiting; waiting.note = "Onay?"
    let problems = SessionStatus(problems: ["build kırık"])
    #expect(resolveState(activity: waiting, agent: nil, registry: nil, alive: true, seenAlive: true, status: problems) == (.waiting, "Onay?"))
    waiting.note = nil
    #expect(resolveState(activity: waiting, agent: nil, registry: nil, alive: true, seenAlive: true, status: problems) == (.waiting, "build kırık"))
    var done = Activity(); done.state = .turnDone
    #expect(resolveState(activity: done, agent: nil, registry: nil, alive: true, seenAlive: true, status: problems) == (.problem, "build kırık"))
}
@Test func agentViewNotificationsAreIgnored() {
    let a = reduceEvents([ev("UserPromptSubmit"), ev("Notification", nt: "agent_needs_input", msg: "başka session"),
                          ev("Notification", nt: "agent_completed")])
    #expect(a.state == .working && a.note == nil)
}
@Test func ownFilePostToolUseEndsWaiting() {
    let a = reduceEvents([ev("PreToolUse", tool: "Bash", target: "ls"), ev("Notification", nt: "permission_prompt", msg: "izin"),
                          ev("PostToolUse", tool: "Write", target: "/Users/o/.session-radar/status/s.json")])
    #expect(a.state == .working && a.note == nil && a.action == "Bash · ls" && a.touched.isEmpty)
}
@Test func idlePromptEndsInterruptedTurn() {
    var a = reduceEvents([ev("UserPromptSubmit"), ev("PreToolUse", tool: "Bash", target: "npm test")])
    apply(ev("Notification", nt: "idle_prompt", msg: "Claude is waiting for your input"), to: &a)
    #expect(a.state == .turnDone && a.action == nil)
}
@Test func idlePromptKeepsBackgroundWaitAndQuestions() {
    var bg = reduceEvents([ev("UserPromptSubmit"), ev("Stop", bg: 1)])
    apply(ev("Notification", nt: "idle_prompt"), to: &bg)
    #expect(bg.state == .working)
    var q = reduceEvents([ev("UserPromptSubmit"), ev("Stop", msg: "Devam edeyim mi?", q: true)])
    apply(ev("Notification", nt: "idle_prompt"), to: &q)
    #expect(q.state == .waiting)
}
@Test func repeatedIdlePromptKeepsBackgroundWait() {
    var a = reduceEvents([ev("UserPromptSubmit"), ev("Stop", bg: 1)])
    apply(ev("Notification", nt: "idle_prompt"), to: &a)
    apply(ev("Notification", nt: "idle_prompt"), to: &a)
    #expect(a.state == .working)
}
@Test func newPromptClearsStaleBackgroundWait() {
    var a = reduceEvents([ev("UserPromptSubmit"), ev("Stop", bg: 1), ev("UserPromptSubmit")])
    apply(ev("Notification", nt: "idle_prompt"), to: &a)
    #expect(a.state == .turnDone && a.action == nil)
}
@Test func waitingSinceSetOnceAndCleared() {
    var a = reduceEvents([ev("PreToolUse", tool: "Bash", target: "ls", ts: 10), ev("Notification", nt: "permission_prompt", msg: "izin", ts: 11),
                          ev("Notification", nt: "idle_prompt", ts: 70)])
    #expect(a.waitingSince == 11)
    apply(ev("PostToolUse", tool: "Bash", target: "ls", ts: 80), to: &a)
    #expect(a.waitingSince == nil)
}
@Test func permissionPromptNoteShowsPendingTool() {
    let a = reduceEvents([ev("PreToolUse", tool: "Bash", target: "npm run migrate"),
                          ev("Notification", nt: "permission_prompt", msg: "Claude needs your permission to use Bash")])
    #expect(a.note == "Bash · npm run migrate")
    let b = reduceEvents([ev("Notification", nt: "permission_prompt", msg: "Claude needs your permission to use Bash")])
    #expect(b.note == "Claude needs your permission to use Bash")
}
