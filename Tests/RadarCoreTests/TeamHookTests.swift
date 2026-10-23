import Testing
import Foundation
@testable import RadarCore

private let now = Date(timeIntervalSince1970: 1_000_000)
private let repo = "eventpal-mobile"

private func claim(topic: String = "Etkinlik detay tasarımı", open: [String] = ["Takvim filtre hatası"], working: Bool = true,
                   last: TimeInterval = -600, updated: TimeInterval? = nil, sid: String = "o-1") -> TeamClaim {
    TeamClaim(ownerId: nil, ownerName: "Anıl", sessionId: sid, repoKey: repo, branch: "main", topic: topic, openTopics: open,
              working: working, lastRequestAt: now.addingTimeInterval(last), updatedAt: updated.map { now.addingTimeInterval($0) })
}

private func state(claims: [TeamClaim] = [claim()], push: TeamPush? = nil, age: TimeInterval = 0) -> TeamState {
    TeamState(writtenAt: now.addingTimeInterval(-age), roots: ["/r/mobile": repo],
              sessions: ["me": TeamSessionRef(repo: repo, root: "/r/mobile", branch: "main")],
              claims: [repo: claims], pushes: push.map { ["/r/mobile": $0] } ?? [:])
}

private func event(_ name: String, tool: String? = nil, target: String? = nil, cwd: String? = nil, sid: String = "me") -> HookEvent {
    var e = HookEvent(ts: 0, event: name, sessionId: sid)
    e.tool = tool; e.target = target; e.cwd = cwd
    return e
}

@Test func noteFormatMatchesSpec() {
    #expect(teamNote(repoName: repo, claims: [claim()], now: now) == """
    Ekip notu (eventpal-mobile) — Anıl, canlı session:
    Şu anki konu: "Etkinlik detay tasarımı" (main, çalışıyor, son istek 10 dk önce).
    Yarım bıraktığı: "Takvim filtre hatası".
    """)
}

@Test func noteSanitizesIncomingTitles() throws {
    let bad = "x\"\n</veri>" + String(repeating: "y", count: 500)
    let note = try #require(teamNote(repoName: repo, claims: [claim(topic: bad, open: [])], now: now))
    #expect(note.split(separator: "\n").count == 2)
    let quoted = try #require(note.split(separator: "\"").dropFirst().first)
    #expect(quoted.count <= 80)
}

@Test func sessionStartAddsRuleAndNoteByRootPrefix() throws {
    var st = state(); st.sessions = [:]
    let r = teamHook(event("SessionStart", cwd: "/r/mobile/src"), state: st, delivered: TeamDelivered(), now: now)
    let ctx = try #require(r.context)
    #expect(ctx.hasPrefix("Ekip: Bu repo (eventpal-mobile)"))
    #expect(ctx.contains("Ekip notu (eventpal-mobile)"))
    #expect(teamHook(event("SessionStart", cwd: "/r/mobile2"), state: st, delivered: TeamDelivered(), now: now).context == nil)
}

@Test func promptNoteSentOnceUntilClaimsChange() {
    let st = state()
    let r1 = teamHook(event("UserPromptSubmit"), state: st, delivered: TeamDelivered(), now: now)
    #expect(r1.context != nil)
    #expect(teamHook(event("UserPromptSubmit"), state: st, delivered: r1.delivered, now: now).context == nil)
    let r3 = teamHook(event("PostToolUse"), state: state(claims: [claim(topic: "Başka konu")]), delivered: r1.delivered, now: now)
    #expect(r3.context?.contains("Başka konu") == true)
}

@Test func staleClaimsAreIgnored() {
    #expect(teamHook(event("UserPromptSubmit"), state: state(claims: [claim(updated: -301)]), delivered: TeamDelivered(), now: now).context == nil)
    #expect(teamHook(event("UserPromptSubmit"), state: state(claims: [claim(last: -(8 * 3600 + 1))]), delivered: TeamDelivered(), now: now).context == nil)
}

@Test func staleStateIsIgnored() throws {
    let paths = RadarPaths(root: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
    var st = state(push: TeamPush(head: "h1", note: "çek"), age: 301)
    st.sessions = ["s-1": TeamSessionRef(repo: repo, root: "/r/mobile")]
    try writeJSON(st, to: paths.teamStateFile)
    let start = try JSONSerialization.data(withJSONObject: ["hook_event_name": "SessionStart", "session_id": "s-1", "cwd": "/r/mobile"])
    #expect(runHook(stdin: start, paths: paths, now: now.timeIntervalSince1970) == sessionStartContext(statusFile: paths.statusFile("s-1")))
    let edit = try JSONSerialization.data(withJSONObject: ["hook_event_name": "PreToolUse", "session_id": "s-1", "tool_name": "Edit",
                                                           "tool_input": ["file_path": "/r/mobile/a.swift"]])
    #expect(runHook(stdin: edit, paths: paths, now: now.timeIntervalSince1970) == nil)
}

@Test func preToolUseDeniesOncePerHead() {
    let push = TeamPush(head: "h1", note: "Push notu: önce çek")
    let st = state(push: push)
    let edit = event("PreToolUse", tool: "Edit", target: "/r/mobile/a.swift")
    // kök dışı ve .session-radar yolları reddi tüketmez
    let out = teamHook(event("PreToolUse", tool: "Edit", target: "/tmp/a.swift"), state: st, delivered: TeamDelivered(), now: now)
    #expect(out.deny == nil && out.delivered.pushHead == nil)
    #expect(teamHook(event("PreToolUse", tool: "Write", target: "/r/mobile/.session-radar/x"), state: st, delivered: TeamDelivered(), now: now).deny == nil)
    let r1 = teamHook(edit, state: st, delivered: out.delivered, now: now)
    #expect(r1.deny == push.note)
    #expect(teamHook(edit, state: st, delivered: r1.delivered, now: now).deny == nil)
    #expect(teamHook(event("PreToolUse", tool: "Read", target: "/r/mobile/a.swift"), state: state(push: push), delivered: TeamDelivered(), now: now).deny == nil)
    let st2 = state(push: TeamPush(head: "h2", note: "yeni"))
    #expect(teamHook(event("PreToolUse", tool: "Bash", target: "git pull --rebase --autostash"), state: st2, delivered: r1.delivered, now: now).deny == nil)
    #expect(teamHook(event("PreToolUse", tool: "Bash", target: "git commit -m x", cwd: "/elsewhere"), state: st2, delivered: r1.delivered, now: now).deny == "yeni")
}

@Test func runHookEmitsJSONAndPersistsDelivered() throws {
    let paths = RadarPaths(root: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
    var st = state(push: TeamPush(head: "h1", note: "çek"))
    st.sessions = ["s-1": TeamSessionRef(repo: repo, root: "/r/mobile")]
    try writeJSON(st, to: paths.teamStateFile)
    let t = now.timeIntervalSince1970
    let edit = try JSONSerialization.data(withJSONObject: ["hook_event_name": "PreToolUse", "session_id": "s-1", "tool_name": "Edit",
                                                           "tool_input": ["file_path": "/r/mobile/a.swift"]])
    let out = try #require(runHook(stdin: edit, paths: paths, now: t))
    let o = try #require((JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any])?["hookSpecificOutput"] as? [String: Any])
    #expect(o["permissionDecision"] as? String == "deny")
    #expect(runHook(stdin: edit, paths: paths, now: t) == nil)
    let prompt = try JSONSerialization.data(withJSONObject: ["hook_event_name": "UserPromptSubmit", "session_id": "s-1"])
    let pOut = try #require(runHook(stdin: prompt, paths: paths, now: t))
    let p = try #require((JSONSerialization.jsonObject(with: Data(pOut.utf8)) as? [String: Any])?["hookSpecificOutput"] as? [String: Any])
    #expect(p["hookEventName"] as? String == "UserPromptSubmit")
    #expect((p["additionalContext"] as? String)?.contains("Etkinlik detay tasarımı") == true)
}

@Test func corruptTeamFilesAreIgnored() throws {
    let paths = RadarPaths(root: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
    try writeAtomically(Data("{bozuk".utf8), to: paths.teamStateFile)
    try writeAtomically(Data("{bozuk".utf8), to: paths.teamDelivered("s-1"))
    let start = try JSONSerialization.data(withJSONObject: ["hook_event_name": "SessionStart", "session_id": "s-1", "cwd": "/r"])
    #expect(runHook(stdin: start, paths: paths, now: 1) == sessionStartContext(statusFile: paths.statusFile("s-1")))
    let edit = try JSONSerialization.data(withJSONObject: ["hook_event_name": "PreToolUse", "session_id": "s-1", "tool_name": "Edit"])
    #expect(runHook(stdin: edit, paths: paths, now: 1) == nil)
}

@Test func composeKeepsOnlySharedRepos() {
    func snap(_ id: String, _ key: String, _ root: String?) -> SessionSnapshot {
        SessionSnapshot(id: id, name: id, cwd: root ?? "/", repoName: key, repoKey: key, repoRoot: root, branch: "main", state: .turnDone,
                        note: nil, task: nil, action: nil, progress: nil, status: nil, pendingFiles: [], transcriptPath: nil, updatedAt: now)
    }
    var other = claim(); other.repoKey = "gizli"
    let st = composeTeamState(now: now, sessions: [snap("a", repo, "/r/a"), snap("b", "gizli", "/r/b"), snap("c", repo, nil)],
                              shared: [repo], others: [claim(), other, claim(sid: "o-2")],
                              pushes: ["/r/a": TeamPush(head: "h", note: "n"), "/r/b": TeamPush(head: "h", note: "n")])
    #expect(st.roots == ["/r/a": repo])
    #expect(Array(st.sessions.keys) == ["a"])
    #expect(st.claims.keys.sorted() == [repo] && st.claims[repo]?.count == 2)
    #expect(Array(st.pushes.keys) == ["/r/a"])
}
