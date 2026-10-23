import Foundation

public struct TeamPush: Codable, Equatable, Sendable {
    public var head: String; public var note: String
    public init(head: String, note: String) { self.head = head; self.note = note }
}
public struct TeamSessionRef: Codable, Equatable, Sendable {
    public var repo: String; public var root: String; public var branch: String?
    public init(repo: String, root: String, branch: String? = nil) { self.repo = repo; self.root = root; self.branch = branch }
}
public struct TeamState: Codable, Equatable, Sendable {
    public var writtenAt: Date
    /// checkout kökü -> repo anahtarı
    public var roots: [String: String]
    public var sessions: [String: TeamSessionRef]
    /// repo anahtarı -> karşı tarafın kayıtları
    public var claims: [String: [TeamClaim]]
    /// checkout kökü -> bekleyen push
    public var pushes: [String: TeamPush]
    public init(writtenAt: Date, roots: [String: String] = [:], sessions: [String: TeamSessionRef] = [:],
                claims: [String: [TeamClaim]] = [:], pushes: [String: TeamPush] = [:]) {
        self.writtenAt = writtenAt; self.roots = roots; self.sessions = sessions; self.claims = claims; self.pushes = pushes
    }
}
public struct TeamDelivered: Codable, Equatable, Sendable {
    public var claimsKey: String?; public var pushHead: String?
    public init(claimsKey: String? = nil, pushHead: String? = nil) { self.claimsKey = claimsKey; self.pushHead = pushHead }
}
public struct TeamSettings: Codable, Equatable, Sendable {
    public var name = ""; public var email = ""; public var enabled = false; public var sharedRepos: [String] = []
    public init() {}
}

public let teamStaleAfter: TimeInterval = 300

public func readJSON<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
    return try? dec.decode(type, from: data)
}

public func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
    let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
    try writeAtomically(try enc.encode(value), to: url)
}

public func composeTeamState(now: Date, sessions: [SessionSnapshot], shared: Set<String>,
                             others: [TeamClaim], pushes: [String: TeamPush]) -> TeamState {
    var st = TeamState(writtenAt: now)
    for s in sessions {
        guard let key = s.repoKey, shared.contains(key), let root = s.repoRoot else { continue }
        st.roots[root] = key
        st.sessions[s.id] = TeamSessionRef(repo: key, root: root, branch: s.branch)
    }
    for c in others where shared.contains(c.repoKey) { st.claims[c.repoKey, default: []].append(c) }
    st.pushes = pushes.filter { st.roots[$0.key] != nil }
    return st
}

public func teamRule(repoName: String) -> String {
    """
    Ekip: Bu repo (\(repoName)) ekip arkadaşlarınla ortak. Session Radar, karşı tarafın canlı session'larındaki konuları "Ekip notu" ile bildirir.
    - Kullanıcının istediği iş ekip notundaki bir konuyla aynı ya da çok yakınsa, işe girmeden kullanıcıya söyle ve devam edip etmeyeceğini sor. Kullanıcı devam de derse devam et.
    - "Push notu" gelirse dosya düzenlemeden ve commit'e geçmeden önce `git pull --rebase --autostash` çalıştır. Çakışma çıkarsa `git rebase --abort` ile geri dön, tarafı kendin seçme; hangi dosyaların kimin commit'iyle çakıştığını kullanıcıya söyle ve sor.
    """
}

public func teamNote(repoName: String, claims: [TeamClaim], now: Date) -> String? {
    guard !claims.isEmpty else { return nil }
    func ago(_ d: Date) -> String {
        let s = now.timeIntervalSince(d)
        return s < 60 ? "az önce" : s < 3600 ? "\(Int(s / 60)) dk önce" : "\(Int(s / 3600)) sa önce"
    }
    return claims.map { c in
        var info = [c.branch.map { teamText($0, max: 80) }, c.working ? "çalışıyor" : "boşta"].compactMap { $0 }
        info.append("son istek \(ago(c.lastRequestAt))")
        var lines = ["Ekip notu (\(teamText(repoName, max: 80))) — \(teamText(c.ownerName, max: 40)), canlı session:",
                     "Şu anki konu: \"\(teamText(c.topic, max: 80))\" (\(info.joined(separator: ", ")))."]
        let open = c.openTopics.map { "\"\(teamText($0, max: 80))\"" }
        if !open.isEmpty { lines.append("Yarım bıraktığı: \(open.joined(separator: ", ")).") }
        return lines.joined(separator: "\n")
    }.joined(separator: "\n\n")
}

public struct TeamHookResult: Equatable, Sendable {
    public var context: String?; public var deny: String?; public var delivered: TeamDelivered
}

private func inside(_ path: String, _ root: String) -> Bool { path == root || path.hasPrefix(root + "/") }

public func teamHook(_ e: HookEvent, state: TeamState?, delivered: TeamDelivered, now: Date) -> TeamHookResult {
    var r = TeamHookResult(context: nil, deny: nil, delivered: delivered)
    guard let state, now.timeIntervalSince(state.writtenAt) <= teamStaleAfter else { return r }

    let ref: TeamSessionRef
    if let s = state.sessions[e.sessionId] {
        ref = s
    } else if let cwd = e.cwd, let root = state.roots.keys.filter({ inside(cwd, $0) }).max(by: { $0.count < $1.count }),
              let key = state.roots[root] {
        ref = TeamSessionRef(repo: key, root: root)
    } else { return r }

    let claims = (state.claims[ref.repo] ?? []).filter {
        now.timeIntervalSince($0.lastRequestAt) < claimMaxAge && ($0.updatedAt.map { now.timeIntervalSince($0) < teamStaleAfter } ?? true)
    }
    let key = claims.isEmpty ? nil : claims.map { "\($0.ownerName)|\($0.sessionId)|\($0.topic)|\($0.openTopics)" }.sorted().joined(separator: "\n")
    let note = teamNote(repoName: ref.repo, claims: claims, now: now)

    switch e.event {
    case "SessionStart":
        r.context = teamRule(repoName: ref.repo) + (note.map { "\n\n" + $0 } ?? "")
        r.delivered.claimsKey = key
    case "UserPromptSubmit", "PostToolUse":
        if key != nil && key != delivered.claimsKey { r.context = note }
        r.delivered.claimsKey = key
    case "PreToolUse":
        guard let push = state.pushes[ref.root], push.head != delivered.pushHead else { break }
        let target = e.target ?? ""
        let isEdit = ["Edit", "Write", "MultiEdit", "NotebookEdit"].contains(e.tool ?? "")
            && inside(target, ref.root) && !target.contains("/.session-radar/")
        let isGit = e.tool == "Bash" && target.contains("git ") && (target.contains(" commit") || target.contains(" push"))
        if isEdit || isGit { r.deny = push.note; r.delivered.pushHead = push.head }
    default: break
    }
    return r
}
