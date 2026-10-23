import Testing
import Foundation
@testable import RadarCore

func ev(_ name: String, tool: String? = nil, target: String? = nil, nt: String? = nil, msg: String? = nil,
        q: Bool? = nil, bg: Int? = nil) -> HookEvent {
    HookEvent(ts: 1, event: name, sessionId: "s", cwd: nil, transcriptPath: nil, tool: tool, target: target,
              notificationType: nt, message: msg, endsWithQuestion: q, backgroundTasks: bg)
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
    #expect(resolveState(activity: ended, agent: nil, alive: true, status: nil).state == .closed)
    #expect(resolveState(activity: working, agent: nil, alive: false, status: nil) == (.problem, "Session beklenmedik şekilde kapandı"))
    #expect(resolveState(activity: Activity(), agent: nil, alive: false, status: nil).state == .closed)
    #expect(resolveState(activity: working, agent: nil, alive: true, status: SessionStatus(problems: ["build kırık"])) == (.problem, "build kırık"))
}
@Test func resolveFallsBackToAgentWithoutEvents() {
    let bg = AgentEntry(id: "x", pid: 1, sessionId: "s", name: nil, cwd: "/r", kind: "background", startedAt: nil, status: nil, state: "blocked")
    let it = AgentEntry(id: nil, pid: 2, sessionId: "s", name: nil, cwd: "/r", kind: "interactive", startedAt: nil, status: "busy", state: nil)
    #expect(resolveState(activity: nil, agent: bg, alive: true, status: nil).state == .waiting)
    #expect(resolveState(activity: nil, agent: it, alive: true, status: nil).state == .working)
}
@Test func resolveStoppedBackgroundIsClosed() {
    let stopped = AgentEntry(id: "x", pid: nil, sessionId: "s", name: nil, cwd: "/r", kind: "background", startedAt: nil, status: nil, state: "blocked")
    #expect(resolveState(activity: nil, agent: stopped, alive: false, status: nil).state == .closed)
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
