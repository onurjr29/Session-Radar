import Foundation
import RadarCore

/// Ekip döngüsü: kayıtları paylaşır, gelen push'ları izler, hook için yerel durumu yazar.
actor TeamSync {
    private let paths: RadarPaths
    private let client: SupabaseClient?
    private var notified: Set<String> = []
    private var lastFetch: [String: Date] = [:]
    /// giriş/çıkışta artar; ağ beklenirken değiştiyse eski oturum auth.json'a geri yazılmaz
    private var authEpoch = 0

    init(paths: RadarPaths, config: SupabaseConfig?) {
        self.paths = paths
        client = config.map { SupabaseClient(config: $0) }
    }

    func step(sessions: [SessionSnapshot], histories: [String: SessionHistory], now: Date) async
        -> (notifications: [RadarNotification], down: Bool) {
        let settings = readJSON(TeamSettings.self, from: paths.teamSettingsFile) ?? TeamSettings()
        guard settings.enabled, !settings.sharedRepos.isEmpty else {
            try? FileManager.default.removeItem(at: paths.teamStateFile)
            return ([], false)
        }
        let shared = Set(settings.sharedRepos)

        let live = sessions.filter { s in s.alive && s.repoKey.map { shared.contains($0) } == true }
        let roots = Set(live.compactMap(\.repoRoot))
        let due = roots.filter { now.timeIntervalSince(lastFetch[$0] ?? .distantPast) >= 180 }
        for r in due { lastFetch[r] = now }
        // ponytail: fetch'ler sırayla; erişilemeyen her remote adımı ~10 sn uzatır, kök sayısı artarsa paralel yap
        let incoming = await Task.detached {
            for r in due { _ = fetchUpstream(cwd: r) }
            var out: [String: IncomingPush] = [:]
            for r in roots { out[r] = incomingPush(cwd: r) }
            return out
        }.value
        var pushes: [String: TeamPush] = [:]
        var sightings: [PushSighting] = []
        for (root, push) in incoming.sorted(by: { $0.key < $1.key }) {
            let here = sessions.filter { $0.repoRoot == root }
            let name = here.compactMap(\.repoName).first ?? URL(fileURLWithPath: root).lastPathComponent
            pushes[root] = TeamPush(head: push.head, note: pushNote(repoName: name, push: push))
            guard let branch = live.first(where: { $0.repoRoot == root && $0.branch != nil })?.branch else { continue }
            let mine = here.reduce(into: Set<String>()) { $0.formUnion($1.pendingFiles) }
            sightings.append(PushSighting(root: root, repoName: name, branch: branch, push: push,
                                          overlap: mine.intersection(push.files).count))
        }

        let claims = buildClaims(sessions, histories: histories, owner: settings.name, shared: shared, now: now)
        var others: [TeamClaim] = []
        var down = false
        if let client, !settings.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let auth = readJSON(AuthSession.self, from: paths.teamAuthFile) {
            let epoch = authEpoch
            do {
                let s = try await client.authorized(auth, now: now)
                guard epoch == authEpoch else { throw CancellationError() }
                if s != auth { try writeJSON(s, to: paths.teamAuthFile) }
                try await client.publish(claims, as: s)
                others = try await client.fetchOthers(as: s, since: now.addingTimeInterval(-teamStaleAfter))
            } catch {
                // giriş/çıkış yüzünden yarıda kaldıysa paylaşım kapalı sayılmaz
                down = epoch == authEpoch
            }
        }

        try? writeJSON(composeTeamState(now: now, sessions: sessions, shared: shared, others: others, pushes: pushes),
                       to: paths.teamStateFile)
        let r = pushNotifications(sightings, notified: notified)
        notified = r.notified
        return (r.notes, down)
    }

    /// Hata metni döner; başarıda nil.
    func signIn(email: String, password: String) async -> String? {
        guard let client else { return "Supabase ayarı yok" }
        do {
            let s = try await client.signIn(email: email, password: password, now: Date())
            try writeJSON(s, to: paths.teamAuthFile)
            authEpoch += 1
            return nil
        } catch SupabaseError.http(let code, _) {
            return code == 400 ? "E-posta ya da parola hatalı" : "Giriş yapılamadı (HTTP \(code))"
        } catch {
            return "Giriş yapılamadı: \(error.localizedDescription)"
        }
    }

    /// Oturum dosyası hemen silinir; kendi kayıtlarım arka planda silinir ki karşı taraf 5 dk bayat kayıt görmesin.
    func signOut() {
        let auth = readJSON(AuthSession.self, from: paths.teamAuthFile)
        try? FileManager.default.removeItem(at: paths.teamAuthFile)
        authEpoch += 1
        guard let client, let auth else { return }
        Task { _ = try? await client.publish([], as: client.authorized(auth, now: Date())) }
    }
}
