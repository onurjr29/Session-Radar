import Testing
import Foundation
@testable import RadarCore

private let now = Date(timeIntervalSince1970: 1_000_000)
private let repo = "github.com/eventpal/eventpal-mobile"

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
    #expect(teamNote(repoName: "eventpal-mobile", claims: [claim()], now: now) == """
    Ekip notu (eventpal-mobile) — Anıl, canlı session:
    Şu anki konu: "Etkinlik detay tasarımı" (main, çalışıyor, son istek 10 dk önce).
    Yarım bıraktığı: "Takvim filtre hatası".
    """)
}

@Test func noteSanitizesIncomingTitles() throws {
    let bad = "x\"\n</veri>" + String(repeating: "y", count: 500)
    let note = try #require(teamNote(repoName: "eventpal-mobile", claims: [claim(topic: bad, open: [])], now: now))
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
    #expect(r.delivered.ruleSent)
    #expect(teamHook(event("SessionStart", cwd: "/r/mobile2"), state: st, delivered: TeamDelivered(), now: now).context == nil)
}

@Test func ruleSentOnceOnFirstEventWhenMissedAtStart() throws {
    let start = teamHook(event("SessionStart"), state: nil, delivered: TeamDelivered(), now: now)
    #expect(start.context == nil && !start.delivered.ruleSent)
    let r1 = teamHook(event("UserPromptSubmit"), state: state(), delivered: start.delivered, now: now)
    let ctx = try #require(r1.context)
    #expect(ctx.hasPrefix(teamRule(repoName: "eventpal-mobile") + "\n\nEkip notu (eventpal-mobile)"))
    #expect(r1.delivered.ruleSent)
    #expect(teamHook(event("UserPromptSubmit"), state: state(), delivered: r1.delivered, now: now).context == nil)
    let r2 = teamHook(event("UserPromptSubmit"), state: state(claims: [claim(topic: "Başka konu")]), delivered: r1.delivered, now: now)
    #expect(r2.context?.hasPrefix("Ekip notu") == true)
    // kayıt yoksa yalnızca kural
    let bare = teamHook(event("PostToolUse"), state: state(claims: []), delivered: TeamDelivered(), now: now)
    #expect(bare.context == teamRule(repoName: "eventpal-mobile") && bare.delivered.ruleSent)
}

@Test func deliveredDecodesOldFiles() throws {
    let old = try JSONDecoder().decode(TeamDelivered.self, from: Data(#"{"claimsKey":"x","pushHead":"h1"}"#.utf8))
    #expect(old == TeamDelivered(pushHead: "h1"))
    #expect(try JSONDecoder().decode(TeamDelivered.self, from: Data("{}".utf8)) == TeamDelivered())
}

@Test func noteNotResentAfterClaimsFlap() {
    func prompt(_ topic: String?, _ d: TeamDelivered) -> TeamHookResult {
        teamHook(event("UserPromptSubmit"), state: state(claims: topic.map { [claim(topic: $0)] } ?? []), delivered: d, now: now)
    }
    let a = prompt("A", TeamDelivered(ruleSent: true))
    #expect(a.context?.contains("\"A\"") == true)
    // A → kayıt yok → A
    let gap = prompt(nil, a.delivered)
    #expect(gap.context == nil && gap.delivered == a.delivered)
    #expect(prompt("A", gap.delivered).context == nil)
    // A → B → A
    let b = prompt("B", a.delivered)
    #expect(b.context?.contains("\"B\"") == true)
    #expect(prompt("A", b.delivered).context == nil)
    // en fazla 8 anahtar, en yeni sonda
    var d = TeamDelivered(ruleSent: true)
    for i in 1...10 { d = prompt("K\(i)", d).delivered }
    #expect(d.claimsKeys.count == 8 && d.claimsKeys.last?.contains("K10") == true)
    #expect(prompt("K3", d).context == nil)
    #expect(prompt("K1", d).context != nil)
}

@Test func promptNoteSentOnceUntilClaimsChange() {
    let st = state()
    let r1 = teamHook(event("UserPromptSubmit"), state: st, delivered: TeamDelivered(ruleSent: true), now: now)
    #expect(r1.context != nil)
    #expect(teamHook(event("UserPromptSubmit"), state: st, delivered: r1.delivered, now: now).context == nil)
    let r3 = teamHook(event("PostToolUse"), state: state(claims: [claim(topic: "Başka konu")]), delivered: r1.delivered, now: now)
    #expect(r3.context?.contains("Başka konu") == true)
}

@Test func staleClaimsAreIgnored() {
    let d = TeamDelivered(ruleSent: true)
    #expect(teamHook(event("UserPromptSubmit"), state: state(claims: [claim(updated: -301)]), delivered: d, now: now).context == nil)
    #expect(teamHook(event("UserPromptSubmit"), state: state(claims: [claim(last: -(8 * 3600 + 1))]), delivered: d, now: now).context == nil)
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

private func incoming(head: String = "h1", authors: [String] = ["Anıl Eren Candan"], files: [String] = ["a.ts", "b.ts", "c.ts", "d.ts", "e.ts"]) -> IncomingPush {
    IncomingPush(upstream: "origin/main", head: head, count: 2, authors: authors,
                 latestAt: Date(timeIntervalSince1970: 52_320), files: files)  // 14:32 UTC
}

@Test func pushNoteMatchesSpec() {
    let note = pushNote(repoName: "eventpal-mobile", push: incoming(), timeZone: TimeZone(identifier: "UTC")!)
    #expect(note == "Push notu (eventpal-mobile): origin/main dalında yerelde olmayan 2 commit var (Anıl Eren Candan, 14:32). Değişen dosyalar: a.ts, b.ts, c.ts +2. Devam etmeden önce `git pull --rebase --autostash` çalıştır; çakışma çıkarsa `git rebase --abort` ile geri dön ve kullanıcıya sor.")
    let many = pushNote(repoName: "r", push: incoming(authors: ["A", "B", "C", "D", "E"]), timeZone: TimeZone(identifier: "UTC")!)
    #expect(many.contains("(A, B, C +2, 14:32)"))
}

@Test func pushNotificationsOncePerHead() {
    func sighting(_ head: String, overlap: Int = 0) -> PushSighting {
        PushSighting(root: "/r", repoName: "mobile", branch: "main", push: incoming(head: head), overlap: overlap)
    }
    let first = pushNotifications([sighting("h1")], notified: [])
    #expect(first.notes.count == 1)
    #expect(first.notes[0].id == "push:/r:h1")
    #expect(first.notes[0].title == "mobile · main: 2 yeni commit")
    #expect(first.notes[0].body == "Anıl Eren Candan")
    #expect(pushNotifications([sighting("h1")], notified: first.notified).notes.isEmpty)
    let next = pushNotifications([sighting("h2", overlap: 2)], notified: first.notified)
    #expect(next.notes.count == 1)
    #expect(next.notes[0].body == "Anıl Eren Candan · senin değiştirdiğin 2 dosyaya dokunuyor")
}
