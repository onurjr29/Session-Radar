import Foundation
import Observation
import RadarCore
import UserNotifications

@MainActor @Observable final class RadarStore {
    var sessions: [SessionSnapshot] = []
    var conflicts: [Conflict] = []
    var lastError: String?
    /// yalnızca değiştiğinde atanır; her saniye pencereyi yeniden çizdirmesin
    var histories: [String: SessionHistory] = [:]
    /// pencerede seçili session; gruplama kuyruğunda öncelikli
    var selectedSessionId: String?
    /// dakikada bir ilerler; eşit snapshot ataması yeniden çizdirmediği için bekleme süresi buna bağlı
    var now = Date()
    /// session başına "Soru sor" durumu; popover kapanınca kaybolmasın
    // ponytail: listeden düşen session'ların kaydı silinmez; birkaç kısa metin, uygulama yeniden açılınca gider
    var asks: [String: AskState] = [:]
    /// değişince diske yazılır; TeamSync her adımda dosyadan okur
    var team: TeamSettings {
        didSet {
            guard team != oldValue else { return }
            do { try writeJSON(team, to: paths.teamSettingsFile) } catch {
                lastError = "Ekip ayarları kaydedilemedi: \(error.localizedDescription)"
            }
        }
    }
    var sharingDown = false
    var teamSignedIn: Bool
    /// Info.plist'te SupabaseURL ve SupabaseAnonKey var mı
    let teamConfigured: Bool

    private let paths = RadarPaths.fromEnvironment()
    private let engine: Engine
    private let teamSync: TeamSync
    @ObservationIgnored private var claudePath: String?
    @ObservationIgnored private var lastLookup = Date.distantPast
    @ObservationIgnored private var started = false
    @ObservationIgnored private var slowRunning = false
    @ObservationIgnored private var groupingRunning = false
    @ObservationIgnored private var teamRunning = false

    init() {
        engine = Engine(paths: paths)
        let config = supabaseConfig(Bundle.main.infoDictionary ?? [:])
        teamConfigured = config != nil
        teamSync = TeamSync(paths: paths, config: config)
        team = readJSON(TeamSettings.self, from: paths.teamSettingsFile) ?? TeamSettings()
        teamSignedIn = readJSON(AuthSession.self, from: paths.teamAuthFile) != nil
    }

    func start() {
        guard !started else { return }
        started = true
        do { try paths.prepareDirectories() } catch { lastError = "Veri klasörü hazırlanamadı: \(error.localizedDescription)" }
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
                if n % 30 == 0, !teamRunning {
                    teamRunning = true
                    Task {
                        await teamStep()
                        teamRunning = false
                    }
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// Hata metni döner; başarıda nil.
    func teamSignIn(email: String, password: String) async -> String? {
        let error = await teamSync.signIn(email: email, password: password)
        teamSignedIn = readJSON(AuthSession.self, from: paths.teamAuthFile) != nil
        return error
    }

    func teamSignOut() {
        Task {
            await teamSync.signOut()
            teamSignedIn = readJSON(AuthSession.self, from: paths.teamAuthFile) != nil
        }
    }

    private func teamStep() async {
        let r = await teamSync.step(sessions: sessions, histories: histories, now: Date())
        for n in r.notifications { post(n) }
        if sharingDown != r.down { sharingDown = r.down }
    }

    /// Açık konuyu kapatır; kart bir sonraki tick'i beklemeden güncellenir.
    func closeTopic(_ topicId: Int, in sessionId: String) {
        Task {
            guard let r = await engine.closeTopic(sessionId: sessionId, topicId: topicId) else { return }
            histories[sessionId]?.topics = r.topics
            if let e = r.error { lastError = e }
        }
    }

    /// Taslak soruyu sorar; aynı session'da cevap beklenirken ikinci çağrı başlamaz.
    func sendAsk(_ sessionId: String) {
        let q = (asks[sessionId]?.question ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, asks[sessionId]?.busy != true else { return }
        asks[sessionId, default: AskState()].busy = true
        asks[sessionId]?.answer = nil
        Task {
            let answer = await ask(q, about: sessionId)
            asks[sessionId, default: AskState()].answer = answer
            asks[sessionId]?.busy = false
        }
    }

    private func ask(_ question: String, about sessionId: String) async -> String {
        guard let claude = await claude() else { return "claude bulunamadı" }
        let (status, dialogue) = await engine.askContext(sessionId)
        do {
            return try await runAsk(prompt: buildAskPrompt(question: question, status: status, topics: histories[sessionId]?.topics ?? [], dialogue: dialogue),
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
        // bulunamadıysa login shell araması en fazla dakikada bir
        if claudePath == nil, Date().timeIntervalSince(lastLookup) >= 60 {
            lastLookup = Date()
            let home = NSHomeDirectory(), env = ProcessInfo.processInfo.environment
            claudePath = await Task.detached { resolveClaudePath(home: home, env: env) }.value
        }
        return claudePath
    }

    // agents ve git: süreç çalıştırdıkları için ana thread dışında
    private func refreshSlow() async {
        let claude = await claude()
        let missing = "claude bulunamadı"
        // geçici hata kırmızı yazıda kalmasın; başka hataları silmez
        if claude == nil { lastError = missing } else if lastError == missing { lastError = nil }
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
        let t = Date()
        let r = await engine.tick(now: t)
        if Int(t.timeIntervalSince1970 / 60) != Int(now.timeIntervalSince1970 / 60) { now = t }
        sessions = r.sessions
        conflicts = r.conflicts
        if histories != r.histories { histories = r.histories }
        for n in r.notifications { post(n) }
        groupIfIdle()
    }

    /// Aynı anda tek gruplama işi; Haiku çağrısı ana actor'ü bloklamaz.
    private func groupIfIdle() {
        guard !groupingRunning else { return }
        groupingRunning = true
        Task {
            defer { groupingRunning = false }
            guard let claude = await claude(),
                  let job = await engine.nextJob(selected: selectedSessionId, now: Date()) else { return }
            let output = try? await runAsk(prompt: job.prompt, claudePath: claude, paths: paths)
            await engine.finishJob(sessionId: job.sessionId, output: output)
        }
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

struct AskState: Equatable {
    var question = ""
    var answer: String?
    var busy = false
}

/// Biri eksik ya da boşsa nil.
private func supabaseConfig(_ info: [String: Any]) -> SupabaseConfig? {
    guard let s = info["SupabaseURL"] as? String, !s.isEmpty, let url = URL(string: s),
          let key = info["SupabaseAnonKey"] as? String, !key.isEmpty else { return nil }
    return SupabaseConfig(url: url, anonKey: key)
}

private func mtime(_ url: URL) -> Date? {
    (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
}

/// Session'ın istek geçmişi ve gruplama durumu.
private struct HistoryState {
    var path: String?
    var mtime: Date?
    var cursor = HistoryCursor()
    var requests: [Request] = []
    var topics: [Topic] = []
    var grouped = 0
    var lastRunAt: Date?
    var lastRunLeftBacklog = false
    /// üst üste başarısız gruplama; bekleme 120 sn × 2^n, başarı ya da yeni istek sıfırlar
    var failures = 0
    /// Haiku'ya gönderilmiş, cevabı beklenen parça
    var job: [Request]?
    /// iş başlarken arkasında başka parça var mıydı; çağrı sırasında gelen yeni tur 120 sn beklemesine tabi kalsın
    var jobLeavesBacklog = false
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
    private var histories: [String: HistoryState] = [:]
    /// son tick'in görüntü sırası; gruplama adayları bu sırayla
    private var groupOrder: [(id: String, state: SessionState, alive: Bool)] = []

    init(paths: RadarPaths) {
        self.paths = paths
        reader = EventLogReader(paths: paths)
    }

    func prune() {
        let fm = FileManager.default, cutoff = Date().addingTimeInterval(-7 * 86400)
        for dir in [paths.eventsDir, paths.statusDir, paths.topicsDir, paths.closedDir, paths.teamDir.appending(path: "delivered")] {
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

    func tick(now: Date) -> (sessions: [SessionSnapshot], conflicts: [Conflict], notifications: [RadarNotification],
                             histories: [String: SessionHistory]) {
        ingest()
        registry = loadRegistry(dir: registryDir)
        let list = candidates(now: now)
        seenAlive.formUnion(list.filter(\.seenAlive).map(\.id))
        var kept: [SessionSnapshot] = []
        for c in list {
            let info = transcript(c.id, hint: c.activity?.transcriptPath)
            var inputs = SessionInputs(
                sessionId: c.id, agent: c.agent, registry: c.registry, alive: c.alive, seenAlive: c.seenAlive,
                activity: c.activity, status: status(c.id),
                transcript: info, repo: repos[c.cwd], lastSeen: now, statusAt: statuses[c.id]?.mtime)
            // gizli session'ların istek geçmişi okunmaz; tutulma kararı konulara bağlı değil
            guard shouldKeep(buildSnapshot(inputs), alive: c.alive, now: now) else { continue }
            inputs.topics = history(c.id).topics
            kept.append(buildSnapshot(inputs))
        }
        let ids = Set(list.map(\.id))
        statuses = statuses.filter { ids.contains($0.key) }
        transcripts = transcripts.filter { ids.contains($0.key) }
        histories = histories.filter { ids.contains($0.key) }

        let sessions = sortForDisplay(kept)
        let alive = Dictionary(list.map { ($0.id, $0.alive) }, uniquingKeysWith: { a, _ in a })
        groupOrder = sessions.map { ($0.id, $0.state, alive[$0.id] ?? false) }
        let shown = Dictionary(sessions.compactMap { s in
            histories[s.id].map { (s.id, SessionHistory(requests: $0.requests, topics: $0.topics, grouping: $0.job != nil,
                                       failures: $0.failures)) }
        }, uniquingKeysWith: { a, _ in a })
        let conflicts = findConflicts(sessions)
        let notes = transitions(previous: previous, previousConflictPairs: previousPairs, current: sessions, conflicts: conflicts)
        previous = Dictionary(sessions.map { ($0.id, $0.state) }, uniquingKeysWith: { a, _ in a })
        previousPairs = Set(conflicts.map(\.pairKey))
        return (sessions, conflicts, notes, shown)
    }

    /// Seçilen session'ın gruplanmamış isteklerinden ilk parça ve onun prompt'u.
    func nextJob(selected: String?, now: Date) -> (sessionId: String, prompt: String)? {
        let cands = groupOrder.compactMap { o in
            histories[o.id].map {
                GroupingCandidate(id: o.id, ungrouped: groupableRequests($0.requests, grouped: $0.grouped, working: o.state == .working).count, state: o.state, alive: o.alive,
                                  lastRunAt: $0.lastRunAt, lastRunLeftBacklog: $0.lastRunLeftBacklog, failures: $0.failures)
            }
        }
        guard let id = nextGroupingJob(cands, selected: selected, now: now), let h = histories[id] else { return nil }
        let chunks = chunkRequests(Array(groupableRequests(h.requests, grouped: h.grouped, working: groupOrder.first { $0.id == id }?.state == .working)))
        guard let chunk = chunks.first else { return nil }
        histories[id]?.job = chunk
        histories[id]?.jobLeavesBacklog = chunks.count > 1
        return (id, buildTopicPrompt(existing: h.topics, requests: chunk))
    }

    /// Haiku cevabını işler; geçersizse ya da diske yazılamazsa konular aynen kalır, bekleme iki katına çıkar.
    func finishJob(sessionId id: String, output: String?) {
        // session listeden düştüyse ya da transcript küçüldüyse cevap artık geçersiz
        guard var h = histories[id], let chunk = h.job else { return }
        let now = Date()
        h.job = nil
        h.lastRunAt = now
        h.lastRunLeftBacklog = false
        // bellek diskteki durumun önüne geçmesin: yalnızca kayıt başarılıysa ilerler
        if let output, let response = parseTopicResponse(output),
           let merged = mergeTopics(existing: h.topics, response: response, newRequests: chunk),
           (try? saveTopicFile(TopicFile(sessionId: id, grouped: h.grouped + chunk.count, topics: merged, updatedAt: now),
                               to: paths.topicFile(id))) != nil {
            h.topics = merged
            h.grouped += chunk.count
            h.lastRunLeftBacklog = h.jobLeavesBacklog
            h.failures = 0
        } else {
            h.failures += 1
        }
        histories[id] = h
    }

    /// Konuyu kapatır; güncel konuları ve varsa hata metnini döner (nil: kapatılacak açık konu yok).
    /// Uçuştaki gruplama işi bozulmaz: finishJob h.topics'i temel alır, bayrak korunur.
    func closeTopic(sessionId id: String, topicId: Int) -> (topics: [Topic], error: String?)? {
        guard let h = histories[id], let r = RadarCore.closeTopic(h.topics, id: topicId) else { return nil }
        // kayıt başarısızsa bellek değişmez
        do {
            try saveTopicFile(TopicFile(sessionId: id, grouped: h.grouped, topics: r.topics, updatedAt: Date()), to: paths.topicFile(id))
        } catch { return (h.topics, "Konu kapatılamadı: \(error.localizedDescription)") }
        histories[id]?.topics = r.topics
        do { try appendClosedNote(r.note, to: paths.closedNotes(id)) } catch {
            return (r.topics, "Claude Code'a not yazılamadı: \(error.localizedDescription)")
        }
        return (r.topics, nil)
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

    /// transcript() sonrası çağrılır: yalnızca yeni satırları okur; ilk görüşte konu dosyasını yükler.
    private func history(_ sid: String) -> HistoryState {
        // sözlükten çıkarılır ki diziler kopyalanmadan yerinde değişsin
        var h: HistoryState
        if let cached = histories.removeValue(forKey: sid) { h = cached } else {
            let file = loadTopicFile(paths.topicFile(sid))
            h = HistoryState(topics: file?.topics ?? [], grouped: file?.grouped ?? 0)
        }
        if let t = transcripts[sid], t.path != h.path || t.mtime != h.mtime {
            if t.path != h.path { h.cursor = HistoryCursor(); h.requests = [] }
            let r = readRequests(URL(fileURLWithPath: t.path), from: h.cursor)
            if r.truncated { h.requests = [] }
            if let reply = r.trailingReply, !h.requests.isEmpty { h.requests[h.requests.count - 1].reply = reply }
            h.requests += r.requests
            if !r.requests.isEmpty { h.failures = 0 }
            h.cursor = r.cursor; h.path = t.path; h.mtime = t.mtime
            // dosya küçüldüyse ya da uygulama kapalıyken yeniden yazıldıysa (istek sayısı gruplanandan az):
            // konular silinir, baştan gruplanır
            if r.truncated || h.requests.count < h.grouped {
                h.topics = []; h.grouped = 0; h.job = nil
                try? FileManager.default.removeItem(at: paths.topicFile(sid))
            }
        }
        histories[sid] = h
        return h
    }
}
