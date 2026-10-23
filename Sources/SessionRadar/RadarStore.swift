import Foundation
import Observation
import RadarCore
import UserNotifications

@MainActor @Observable final class RadarStore {
    var sessions: [SessionSnapshot] = []
    var conflicts: [Conflict] = []
    var lastError: String?

    private let paths = RadarPaths.fromEnvironment()
    private let engine: Engine
    @ObservationIgnored private var claudePath: String?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var slowRunning = false

    init() { engine = Engine(paths: paths) }

    func start() {
        guard !started else { return }
        started = true
        Task {
            await engine.prune()
            // ilk anlık görüntü agents ve repo bilgisi geldikten sonra; yoksa açılışta sahte bildirim çıkar
            await refreshSlow()
            for n in 1... {
                await tick()
                if n % 10 == 0, !slowRunning {
                    slowRunning = true
                    Task {
                        await refreshSlow()
                        slowRunning = false
                    }
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func ask(_ question: String, about sessionId: String) async -> String {
        guard let claude = await claude() else { return "claude bulunamadı" }
        let (status, dialogue) = await engine.askContext(sessionId)
        do {
            return try await runAsk(prompt: buildAskPrompt(question: question, status: status, dialogue: dialogue),
                                    claudePath: claude, paths: paths)
        } catch AskError.failed(let m) {
            return "Cevap alınamadı: \(m)"
        } catch AskError.timedOut {
            return "Cevap alınamadı: zaman aşımı"
        } catch {
            return "Cevap alınamadı: \(error.localizedDescription)"
        }
    }

    private func claude() async -> String? {
        if claudePath == nil {
            let home = NSHomeDirectory(), env = ProcessInfo.processInfo.environment
            claudePath = await Task.detached { resolveClaudePath(home: home, env: env) }.value
        }
        return claudePath
    }

    // agents ve git: süreç çalıştırdıkları için ana thread dışında
    private func refreshSlow() async {
        let claude = await claude()
        if claude == nil { lastError = "claude bulunamadı" }
        let agents = await Task.detached { claude.map { loadAgents(claudePath: $0) } ?? [] }.value
        let cwds = await engine.setAgents(agents)
        let repos = await Task.detached {
            var out: [String: RepoInfo] = [:]
            for cwd in cwds { out[cwd] = repoInfo(cwd: cwd) }
            return out
        }.value
        await engine.setRepos(repos)
    }

    private func tick() async {
        let r = await engine.tick(now: Date())
        sessions = r.sessions
        conflicts = r.conflicts
        for n in r.notifications { post(n) }
    }

    private func post(_ n: RadarNotification) {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        let content = UNMutableNotificationContent()
        content.title = n.title
        content.body = n.body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: n.id, content: content, trigger: nil)) { error in
            guard let error else { return }
            let message = "Bildirim gönderilemedi: \(error.localizedDescription)"
            Task { @MainActor in self.lastError = message }
        }
    }
}

private func mtime(_ url: URL) -> Date? {
    (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
}

/// Disk okuyan ve durum tutan her şey burada, ana thread dışında çalışır.
private actor Engine {
    private let paths: RadarPaths
    private let reader: EventLogReader
    private let projectsDir = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/projects")
    private let registryDir = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/sessions")
    private var activities: [String: Activity] = [:]
    private var agents: [AgentEntry] = []
    private var registry: [RegistryEntry] = []
    /// bu çalışmada pid ile canlı görülen session'lar; yalnızca bunlar "beklenmedik şekilde kapandı" olabilir
    private var seenAlive: Set<String> = []
    private var repos: [String: RepoInfo] = [:]
    private var statuses: [String: (mtime: Date?, value: SessionStatus?)] = [:]
    private var transcripts: [String: (path: String, mtime: Date?, value: TranscriptInfo)] = [:]
    private var previous: [String: SessionState]?
    private var previousPairs: Set<String> = []

    init(paths: RadarPaths) {
        self.paths = paths
        reader = EventLogReader(paths: paths)
    }

    func prune() {
        let fm = FileManager.default, cutoff = Date().addingTimeInterval(-7 * 86400)
        for dir in [paths.eventsDir, paths.statusDir] {
            for url in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            where (mtime(url) ?? .distantFuture) < cutoff {
                try? fm.removeItem(at: url)
            }
        }
    }

    /// Repo bilgisi istenecek cwd'leri döner.
    func setAgents(_ list: [AgentEntry]) -> Set<String> {
        // boş liste çoğunlukla `claude agents` hatasıdır; kapanan süreçleri isAlive pid ile zaten yakalar
        if !list.isEmpty { agents = list }
        ingest()
        return Set(candidates(now: Date()).map(\.cwd).filter { !$0.isEmpty })
    }

    func setRepos(_ new: [String: RepoInfo]) {
        // git geçici olarak başarısız olursa eski bilgi kalır; çakışma kaybolup tekrar bildirilmesin
        repos.merge(new) { $1 }
    }

    func askContext(_ sessionId: String) -> (SessionStatus?, [String]) {
        (statuses[sessionId]?.value, transcripts[sessionId]?.value.dialogue ?? [])
    }

    func tick(now: Date) -> (sessions: [SessionSnapshot], conflicts: [Conflict], notifications: [RadarNotification]) {
        ingest()
        registry = loadRegistry(dir: registryDir)
        let list = candidates(now: now)
        seenAlive.formUnion(list.filter(\.seenAlive).map(\.id))
        var kept: [SessionSnapshot] = []
        for c in list {
            let snap = buildSnapshot(SessionInputs(
                sessionId: c.id, agent: c.agent, registry: c.registry, alive: c.alive, seenAlive: c.seenAlive,
                activity: c.activity, status: status(c.id),
                transcript: transcript(c.id, hint: c.activity?.transcriptPath), repo: repos[c.cwd], lastSeen: now))
            if shouldKeep(snap, alive: c.alive, now: now) { kept.append(snap) }
        }
        let ids = Set(list.map(\.id))
        statuses = statuses.filter { ids.contains($0.key) }
        transcripts = transcripts.filter { ids.contains($0.key) }

        let sessions = sortForDisplay(kept)
        let conflicts = findConflicts(sessions)
        let notes = transitions(previous: previous, previousConflictPairs: previousPairs, current: sessions, conflicts: conflicts)
        previous = Dictionary(sessions.map { ($0.id, $0.state) }, uniquingKeysWith: { a, _ in a })
        previousPairs = Set(conflicts.map(\.pairKey))
        return (sessions, conflicts, notes)
    }

    private func ingest() {
        for (sid, events) in reader.poll() {
            var a = activities[sid] ?? Activity()
            for e in events { apply(e, to: &a) }
            activities[sid] = a
        }
    }

    private func candidates(now: Date) -> [Candidate] {
        sessionCandidates(agents: agents, registry: registry, activities: activities, seenAlive: seenAlive, paths: paths, now: now)
    }

    private func status(_ sid: String) -> SessionStatus? {
        let url = paths.statusFile(sid), m = mtime(url)
        if let c = statuses[sid], c.mtime == m { return c.value }
        let value = m == nil ? nil : loadStatus(url)
        statuses[sid] = (m, value)
        return value
    }

    private func transcript(_ sid: String, hint: String?) -> TranscriptInfo? {
        guard let path = hint ?? transcripts[sid]?.path
                ?? findTranscript(sessionId: sid, projectsDir: projectsDir)?.path else { return nil }
        let url = URL(fileURLWithPath: path), m = mtime(url)
        if let c = transcripts[sid], c.path == path, c.mtime == m { return c.value }
        let value = readTranscriptTail(url)
        transcripts[sid] = (path, m, value)
        return value
    }
}
