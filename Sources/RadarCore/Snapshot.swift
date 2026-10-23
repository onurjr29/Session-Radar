import Foundation

public struct SessionInputs: Sendable {
    public var sessionId: String
    public var agent: AgentEntry?
    public var registry: RegistryEntry?
    public var alive: Bool
    public var seenAlive: Bool
    public var activity: Activity?
    public var status: SessionStatus?
    public var transcript: TranscriptInfo?
    public var repo: RepoInfo?
    public var lastSeen: Date
    public var topics: [Topic]
    public var statusAt: Date?

    public init(sessionId: String, agent: AgentEntry?, registry: RegistryEntry?, alive: Bool, seenAlive: Bool,
                activity: Activity?, status: SessionStatus?, transcript: TranscriptInfo?, repo: RepoInfo?, lastSeen: Date,
                topics: [Topic] = [], statusAt: Date? = nil) {
        self.sessionId = sessionId; self.agent = agent; self.registry = registry; self.alive = alive
        self.seenAlive = seenAlive; self.activity = activity
        self.status = status; self.transcript = transcript; self.repo = repo; self.lastSeen = lastSeen
        self.topics = topics; self.statusAt = statusAt
    }
}

/// Sürecin başlangıç zamanı (epoch sn); süreç yoksa nil. Her saniye çağrılır, ps çalıştırmaz.
public func processStartTime(_ pid: Int32) -> Double? {
    var info = kinfo_proc(), size = MemoryLayout<kinfo_proc>.stride
    var mib = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    guard pid > 0, sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
    let t = info.kp_proc.p_starttime
    return Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000
}

public func isAlive(_ agent: AgentEntry?, probe: (Int32) -> Double? = processStartTime) -> Bool {
    guard let pid = agent?.pid else { return false }
    return probe(pid) != nil
}

public struct Candidate: Equatable, Sendable {
    public var id: String
    public var agent: AgentEntry?
    public var registry: RegistryEntry?
    public var activity: Activity?
    public var cwd: String
    public var alive: Bool
    public var seenAlive: Bool
}

/// agents listesi + son 24 saatte olayı olan session'lar; veri kökündekiler hariç.
/// Canlı: kayıt dosyasındaki ya da agents'taki pid çalışıyor, veya son 15 sn içinde olay gelmiş.
public func sessionCandidates(agents: [AgentEntry], registry: [RegistryEntry], activities: [String: Activity],
                              seenAlive: Set<String>, paths: RadarPaths, now: Date,
                              probe: (Int32) -> Double? = processStartTime) -> [Candidate] {
    // aynı session'ın eski süreçten kalmış kaydı olabilir; yalnızca pid'i çalışanlar. Kayıt dosyası süreçten uzun
    // yaşayıp pid başkasına geçmiş olabilir: procStart varsa sürecin başlangıcıyla eşleşmeli
    let live = Dictionary(registry.filter { r in
        guard let start = probe(r.pid) else { return false }
        return r.procStart.flatMap(parseProcStart).map { abs($0 - start) <= 2 } ?? true
    }.map { ($0.sessionId, $0) }, uniquingKeysWith: { a, _ in a })
    let byId = Dictionary(agents.map { ($0.sessionId, $0) }, uniquingKeysWith: { a, _ in a })
    let t = now.timeIntervalSince1970
    let recent = activities.filter { ($0.value.lastEventAt ?? 0) >= t - 86400 }.keys
    return Set(byId.keys).union(recent).compactMap { id in
        let agent = byId[id], reg = live[id], activity = activities[id]
        let cwd = agent?.cwd ?? reg?.cwd ?? activity?.cwd ?? ""
        if !cwd.isEmpty && paths.isInternal(cwd: cwd) { return nil }
        // kayıt dosyası olmayan session (ör. claude -p): hook olayındaki pid. Süreç son olaydan sonra başladıysa pid
        // başkasına geçmiştir; pid'in canlı kaydı varsa o esas (aynı süreç /clear ile başka session'a geçmiş olabilir)
        let owner = activity?.pid.flatMap { p in live.values.contains { $0.pid == p } ? nil : probe(p) }
        let pidAlive = reg != nil || isAlive(agent, probe: probe) || owner.map { $0 <= (activity?.lastEventAt ?? 0) } == true
        // kayıt dosyası ilk olaydan biraz sonra yazılabilir
        let fresh = (activity?.lastEventAt ?? 0) >= t - 15
        return Candidate(id: id, agent: agent, registry: reg, activity: activity, cwd: cwd,
                         alive: pidAlive || fresh, seenAlive: pidAlive || seenAlive.contains(id))
    }
}

private func shortTask(_ prompt: String?) -> String? {
    guard let line = prompt?.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) else { return nil }
    return line.count > 80 ? String(line.prefix(80)) + "…" : line
}

public func buildSnapshot(_ i: SessionInputs) -> SessionSnapshot {
    let cwd = i.agent?.cwd ?? i.activity?.cwd ?? ""
    let name = i.agent?.name ?? i.transcript?.aiTitle ?? URL(fileURLWithPath: cwd).lastPathComponent
    let (state, note) = resolveState(activity: i.activity, agent: i.agent, registry: i.registry, alive: i.alive,
                                     seenAlive: i.seenAlive, status: i.status)
    let todo = i.status?.todo ?? []
    let updatedAt = i.activity?.lastEventAt.map { Date(timeIntervalSince1970: $0) }
        ?? i.agent?.startedAt.map { Date(timeIntervalSince1970: $0 / 1000) }
        ?? i.lastSeen
    let topic = currentTopicSummary(i.topics)
    return SessionSnapshot(
        id: i.sessionId, name: name, cwd: cwd,
        repoName: i.repo?.name, repoKey: i.repo?.key, repoRoot: i.repo?.toplevel, branch: i.repo?.branch,
        state: state, note: note,
        task: i.status?.task ?? shortTask(i.transcript?.lastPrompt),
        action: state == .working ? (i.activity?.action ?? i.transcript?.lastAction) : nil,
        progress: todo.isEmpty ? nil : Progress(done: todo.filter(\.done).count, total: todo.count),
        status: i.status,
        pendingFiles: i.repo.map { pendingTouched(i.activity?.touched ?? [], repo: $0) } ?? [],
        transcriptPath: i.activity?.transcriptPath,
        updatedAt: updatedAt,
        currentTopic: topic.current ?? shortTask(i.transcript?.lastPrompt), openTopics: topic.open,
        waitingSince: state == .waiting ? i.activity?.waitingSince.map { Date(timeIntervalSince1970: $0) } : nil,
        waitingOnTool: state == .waiting && i.activity?.waitingOnTool == true,
        alive: i.alive, statusUpdatedAt: i.statusAt)
}

public func shouldKeep(_ s: SessionSnapshot, alive: Bool, now: Date) -> Bool {
    // ponytail: 24 saatten eski kapanmış session'ların push'lanmamış dosyaları çakışma kontrolüne girmez; gerekirse kişi bazlı kalıcı kayıt
    alive || now.timeIntervalSince(s.updatedAt) < 24 * 3600
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
