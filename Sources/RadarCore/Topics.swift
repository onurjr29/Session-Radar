import Foundation

public struct Topic: Codable, Equatable, Sendable {
    public var id: Int
    public var title: String
    public var state: String   // "active" | "open" | "done"
    public var summary: String
    public var requests: [Int]
    public init(id: Int, title: String, state: String, summary: String, requests: [Int]) {
        self.id = id; self.title = title; self.state = state; self.summary = summary; self.requests = requests
    }
}

public struct TopicFile: Codable, Equatable, Sendable {
    public var sessionId: String
    public var grouped: Int
    public var topics: [Topic]
    public var updatedAt: Date
    public init(sessionId: String, grouped: Int, topics: [Topic], updatedAt: Date) {
        self.sessionId = sessionId; self.grouped = grouped; self.topics = topics; self.updatedAt = updatedAt
    }
}

public struct SessionHistory: Equatable, Sendable {
    public var requests: [Request]
    public var topics: [Topic]
    public var grouping: Bool
    public init(requests: [Request], topics: [Topic], grouping: Bool) {
        self.requests = requests; self.topics = topics; self.grouping = grouping
    }
}

public struct TopicResponse: Decodable, Equatable, Sendable {
    public struct Item: Decodable, Equatable, Sendable {
        public var id: Int; public var title: String; public var state: String; public var summary: String
    }
    public var topics: [Item]
    public var assign: [String: Int]   // "istek no" -> konu id
}

private let maxTextChars = 500
private let maxReplyChars = 300

public func chunkRequests(_ requests: [Request], maxChars: Int = 30_000) -> [[Request]] {
    var chunks: [[Request]] = []
    var cur: [Request] = []
    var used = 0
    for r in requests {
        let cost = min(r.text.count, maxTextChars) + min(r.reply?.count ?? 0, maxReplyChars) + 40
        if !cur.isEmpty && used + cost > maxChars { chunks.append(cur); cur = []; used = 0 }
        cur.append(r); used += cost
    }
    if !cur.isEmpty { chunks.append(cur) }
    return chunks
}

public func buildTopicPrompt(existing: [Topic], requests: [Request]) -> String {
    let fmt = DateFormatter()
    fmt.locale = Locale(identifier: "en_US_POSIX")
    fmt.timeZone = .current
    fmt.dateFormat = "HH:mm"

    let topicLines = existing.isEmpty ? "(yok)" : existing.map { t in
        let range = (t.requests.min().map { lo in "#\(lo)-#\(t.requests.max() ?? lo)" }) ?? "-"
        return "- id \(t.id) | \(t.title) | durum: \(t.state) | istekler: \(range) | özet: \(t.summary)"
    }.joined(separator: "\n")

    let reqLines = requests.map { r in
        let time = r.at.map { fmt.string(from: $0) } ?? "--:--"
        var s = "#\(r.index) [\(time)] \(r.text.prefix(maxTextChars))"
        if let reply = r.reply, !reply.isEmpty { s += "\n  Claude: \(reply.prefix(maxReplyChars))" }
        return s
    }.joined(separator: "\n")

    return """
    Bir Claude Code session'ında kullanıcının isteklerini konu başlıkları altında grupla.

    Kurallar:
    - Yalnızca JSON döndür, başka metin yazma.
    - Şema: {"topics":[{"id":1,"title":"…","state":"active|open|done","summary":"…"}],"assign":{"12":1}}
    - Mevcut tüm konuları gerektiği gibi güncelleyerek döndür. Yeni bir konu gerekirse id değerini mevcut en büyük id'den büyük ver.
    - Her yeni istek numarasını "assign" içinde tam olarak bir konuya ata (anahtar istek numarası, değer konu id'si). Eski istekleri assign'a yazma.
    - Başlıklar en fazla 6 kelime, özetler en fazla 3 cümle olsun ve Türkçe yazılsın.
    - Bir konunun işi bitmişse "done", yarım kalıp sonra dönülecekse "open" olarak işaretle.
    - Başlıklar gereksiz yere değiştirilmesin.

    Mevcut konular:
    \(topicLines)

    Yeni istekler:
    \(reqLines)
    """
}

public func parseTopicResponse(_ output: String) -> TopicResponse? {
    guard let a = output.firstIndex(of: "{"), let b = output.lastIndex(of: "}"), a < b else { return nil }
    return try? JSONDecoder().decode(TopicResponse.self, from: Data(output[a...b].utf8))
}

public func mergeTopics(existing: [Topic], response: TopicResponse, newRequests: [Request]) -> [Topic]? {
    guard !response.topics.contains(where: { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return nil }

    var byId: [Int: Topic] = [:]
    for t in existing { byId[t.id] = t }
    for item in response.topics {
        var t = byId[item.id] ?? Topic(id: item.id, title: "", state: "open", summary: "", requests: [])
        t.title = item.title; t.state = item.state; t.summary = item.summary
        byId[item.id] = t
    }
    for r in newRequests {
        guard let id = response.assign[String(r.index)], byId[id] != nil else { return nil }
        byId[id]?.requests.append(r.index)
    }

    var topics = byId.values.filter { !$0.requests.isEmpty }
    let maxIndex = topics.compactMap { $0.requests.max() }.max()
    for i in topics.indices {
        let isLast = topics[i].requests.max() == maxIndex
        topics[i].state = isLast ? "active" : (topics[i].state == "done" ? "done" : "open")
    }
    return topics.sorted { ($0.requests.min() ?? 0) < ($1.requests.min() ?? 0) }
}

public func loadTopicFile(_ url: URL) -> TopicFile? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
    return try? dec.decode(TopicFile.self, from: data)
}

public func saveTopicFile(_ file: TopicFile, to url: URL) throws {
    let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
    let data = try enc.encode(file)
    // Önce 0600 ile geçici dosya, sonra rename: izin penceresi ve yarım yazım olmaz
    let tmp = url.deletingLastPathComponent().appending(path: ".\(UUID().uuidString).tmp")
    guard FileManager.default.createFile(atPath: tmp.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    if rename(tmp.path, url.path) != 0 {
        try? FileManager.default.removeItem(at: tmp)
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}

public struct GroupingCandidate: Equatable, Sendable {
    public var id: String; public var ungrouped: Int; public var state: SessionState; public var alive: Bool
    public var lastRunAt: Date?; public var lastRunLeftBacklog: Bool
    public init(id: String, ungrouped: Int, state: SessionState, alive: Bool, lastRunAt: Date?, lastRunLeftBacklog: Bool) {
        self.id = id; self.ungrouped = ungrouped; self.state = state; self.alive = alive
        self.lastRunAt = lastRunAt; self.lastRunLeftBacklog = lastRunLeftBacklog
    }
}

/// Sıradaki gruplama işi: seçili session uygunsa o, yoksa uygun ilk aday (adaylar görüntü sırasıyla gelir).
public func nextGroupingJob(_ candidates: [GroupingCandidate], selected: String?, now: Date, gap: TimeInterval = 120) -> String? {
    let eligible = candidates.filter {
        $0.ungrouped > 0
            && ($0.id == selected || ($0.alive && $0.state != .working))
            && ($0.lastRunLeftBacklog || ($0.lastRunAt.map { now.timeIntervalSince($0) >= gap } ?? true))
    }
    return eligible.first { $0.id == selected }?.id ?? eligible.first?.id
}

public func topicStateLabel(_ state: String, sessionClosed: Bool) -> String {
    switch state {
    case "active": return sessionClosed ? "Son konu" : "Şu anki"
    case "done": return "Kapandı"
    default: return "Açık kaldı"
    }
}

public func currentTopicSummary(_ topics: [Topic]) -> (current: String?, open: Int) {
    (topics.last { $0.state == "active" }?.title, topics.filter { $0.state == "open" }.count)
}
