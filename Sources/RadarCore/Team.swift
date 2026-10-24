import Foundation

public struct TeamClaim: Codable, Equatable, Sendable {
    public var ownerId: String?
    public var ownerName: String
    public var sessionId: String
    public var repoKey: String
    public var branch: String?
    public var topic: String
    public var openTopics: [String]
    public var working: Bool
    public var lastRequestAt: Date
    public var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case ownerId = "owner_id", ownerName = "owner_name", sessionId = "session_id", repoKey = "repo_key"
        case branch, topic, openTopics = "open_topics", working, lastRequestAt = "last_request_at", updatedAt = "updated_at"
    }
}

public let claimMaxAge: TimeInterval = 8 * 3600

/// tek satır, kontrol karakteri yok, `"` → `'`, en fazla max code point
func teamText(_ s: String, max: Int) -> String {
    scalarPrefix(oneLine(s.replacingOccurrences(of: "\"", with: "'"), max: max), max)
}

/// Postgres char_length gibi code point sayar; grapheme ortasından kesmez
func scalarPrefix(_ s: String, _ max: Int) -> String {
    var n = 0
    return String(s.prefix { n += $0.unicodeScalars.count; return n <= max })
}

/// Canlı, paylaşılan repodaki ve son 8 saatte istek almış session'ların sahiplik kaydı.
/// Konu yalnızca durum dosyası ya da gruplanmış konulardan gelir; ham prompt'a (snapshot.task) hiç bakılmaz.
public func buildClaims(_ sessions: [SessionSnapshot], histories: [String: SessionHistory],
                        owner: String, shared: Set<String>, now: Date) -> [TeamClaim] {
    sessions.compactMap { s in
        guard s.alive, let key = s.repoKey, shared.contains(key),
              let h = histories[s.id], let last = h.requests.last?.at, now.timeIntervalSince(last) < claimMaxAge
        else { return nil }
        let fresh = s.statusUpdatedAt.map { $0 > last } == true ? s.status?.task : nil
        guard let title = fresh ?? h.topics.last(where: { $0.state == "active" })?.title else { return nil }
        let topic = teamText(title, max: 80)
        guard !topic.isEmpty else { return nil }
        return TeamClaim(ownerId: nil, ownerName: teamText(owner, max: 40), sessionId: s.id, repoKey: scalarPrefix(key, 200),
                         branch: s.branch.map { scalarPrefix($0, 200) },
                         topic: topic, openTopics: h.topics.filter { $0.state == "open" }.prefix(5).map { teamText($0.title, max: 80) },
                         working: s.state == .working, lastRequestAt: last, updatedAt: nil)
    }
}
