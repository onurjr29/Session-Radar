import Foundation

public struct SessionInputs: Sendable {
    public var sessionId: String
    public var agent: AgentEntry?
    public var alive: Bool
    public var activity: Activity?
    public var status: SessionStatus?
    public var transcript: TranscriptInfo?
    public var repo: RepoInfo?
    public var lastSeen: Date

    public init(sessionId: String, agent: AgentEntry?, alive: Bool, activity: Activity?, status: SessionStatus?,
                transcript: TranscriptInfo?, repo: RepoInfo?, lastSeen: Date) {
        self.sessionId = sessionId; self.agent = agent; self.alive = alive; self.activity = activity
        self.status = status; self.transcript = transcript; self.repo = repo; self.lastSeen = lastSeen
    }
}

public func isAlive(_ agent: AgentEntry?, probe: (Int32) -> Bool = { kill($0, 0) == 0 }) -> Bool {
    guard let pid = agent?.pid else { return false }
    return probe(pid)
}

private func shortTask(_ prompt: String?) -> String? {
    guard let line = prompt?.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) else { return nil }
    return line.count > 80 ? String(line.prefix(80)) + "…" : line
}

public func buildSnapshot(_ i: SessionInputs) -> SessionSnapshot {
    let cwd = i.agent?.cwd ?? i.activity?.cwd ?? ""
    let name = i.agent?.name ?? i.transcript?.aiTitle ?? URL(fileURLWithPath: cwd).lastPathComponent
    let (state, note) = resolveState(activity: i.activity, agent: i.agent, alive: i.alive, status: i.status)
    let todo = i.status?.todo ?? []
    let updatedAt = i.activity?.lastEventAt.map { Date(timeIntervalSince1970: $0) }
        ?? i.agent?.startedAt.map { Date(timeIntervalSince1970: $0 / 1000) }
        ?? i.lastSeen
    return SessionSnapshot(
        id: i.sessionId, name: name, cwd: cwd,
        repoName: i.repo?.name, repoKey: i.repo?.key, branch: i.repo?.branch,
        state: state, note: note,
        task: i.status?.task ?? shortTask(i.transcript?.lastPrompt),
        action: state == .working ? (i.activity?.action ?? i.transcript?.lastAction) : nil,
        progress: todo.isEmpty ? nil : Progress(done: todo.filter(\.done).count, total: todo.count),
        status: i.status,
        pendingFiles: i.repo.map { pendingTouched(i.activity?.touched ?? [], repo: $0) } ?? [],
        transcriptPath: i.activity?.transcriptPath,
        updatedAt: updatedAt)
}

public func shouldKeep(_ s: SessionSnapshot, alive: Bool, now: Date) -> Bool {
    // ponytail: 24 saatten eski kapanmış session'ların push'lanmamış dosyaları çakışma kontrolüne girmez; gerekirse kişi bazlı kalıcı kayıt
    alive || now.timeIntervalSince(s.updatedAt) < 24 * 3600
}

public func topicSummary(_ topics: [TopicItem]?) -> (current: String?, open: Int) {
    (topics?.last { $0.state == "active" }?.title, topics?.filter { $0.state == "open" }.count ?? 0)
}

public func sortForDisplay(_ s: [SessionSnapshot]) -> [SessionSnapshot] {
    let rank: [SessionState: Int] = [.waiting: 0, .problem: 1, .working: 2, .turnDone: 3, .closed: 4]
    return s.sorted {
        let (a, b) = (rank[$0.state]!, rank[$1.state]!)
        return a != b ? a < b : $0.updatedAt > $1.updatedAt
    }
}

public func badgeCount(_ s: [SessionSnapshot]) -> Int {
    s.filter { $0.state == .waiting || $0.state == .problem }.count
}

public struct RadarNotification: Equatable, Sendable {
    public var id: String
    public var title: String
    public var body: String
}

public func transitions(previous: [String: SessionState]?, previousConflictPairs: Set<String>,
                        current: [SessionSnapshot], conflicts: [Conflict]) -> [RadarNotification] {
    guard let previous else { return [] }
    var out: [RadarNotification] = []
    for s in current {
        let was = previous[s.id]
        func add(_ title: String, _ body: String) {
            out.append(RadarNotification(id: "\(s.id):\(s.state.rawValue)", title: title, body: body))
        }
        switch s.state {
        case .waiting where was != .waiting: add("\(s.name) seni bekliyor", s.note ?? s.task ?? "")
        case .turnDone where was == .working: add("\(s.name) işini bitirdi", s.task ?? "")
        case .problem where was != .problem: add("\(s.name): sorun var", s.note ?? "")
        default: break
        }
    }
    let names = Dictionary(current.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
    for c in conflicts where !previousConflictPairs.contains(c.pairKey) {
        let more = c.files.count > 3 ? " +\(c.files.count - 3)" : ""
        out.append(RadarNotification(id: "conflict:\(c.pairKey)",
                                     title: "Çakışma: \(names[c.a] ?? c.a) ↔ \(names[c.b] ?? c.b)",
                                     body: c.files.prefix(3).joined(separator: ", ") + more))
    }
    return out
}
