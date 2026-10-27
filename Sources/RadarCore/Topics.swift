import Foundation

public struct Topic: Codable, Equatable, Sendable {
    public var id: Int
    public var title: String
    public var state: String   // "active" | "open" | "done"
    public var summary: String
    public var requests: [Int]
    /// bu konunun sapıldığı konunun id'si; yoksa ana iş
    public var from: Int?
    /// "open" konuda yarım kalan işler (en fazla 3 kısa madde); diğer durumlarda boş
    public var left: [String]
    /// kullanıcı radardan kapattı; konuya yeni istek atanana kadar "done" kalır
    public var closedByUser: Bool
    public init(id: Int, title: String, state: String, summary: String, requests: [Int], from: Int? = nil, left: [String] = [], closedByUser: Bool = false) {
        self.id = id; self.title = title; self.state = state; self.summary = summary; self.requests = requests; self.from = from; self.left = left
        self.closedByUser = closedByUser
    }
    private enum CodingKeys: String, CodingKey { case id, title, state, summary, requests, from, left, closedByUser }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id); title = try c.decode(String.self, forKey: .title)
        state = try c.decode(String.self, forKey: .state); summary = try c.decode(String.self, forKey: .summary)
        requests = try c.decode([Int].self, forKey: .requests); from = try c.decodeIfPresent(Int.self, forKey: .from)
        left = try c.decodeIfPresent([String].self, forKey: .left) ?? []
        closedByUser = try c.decodeIfPresent(Bool.self, forKey: .closedByUser) ?? false
    }
}

public struct TopicFile: Codable, Equatable, Sendable {
    /// istek numaralandırması ya da durum kuralları değişince artar; eşleşmeyen dosya yok sayılır ve session baştan gruplanır
    public static let currentVersion = 4
    public var version = TopicFile.currentVersion
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
    /// üst üste başarısız gruplama sayısı; 3 ve üstünde pencerede uyarı çıkar
    public var failures: Int
    public init(requests: [Request], topics: [Topic], grouping: Bool, failures: Int = 0) {
        self.requests = requests; self.topics = topics; self.grouping = grouping; self.failures = failures
    }
}

public struct TopicResponse: Decodable, Equatable, Sendable {
    public struct Item: Decodable, Equatable, Sendable {
        public var id: Int; public var title: String; public var state: String; public var summary: String
        public var from: Int?
        public var left: [String]
        private enum CodingKeys: String, CodingKey { case id, title, state, summary, from, left }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(Int.self, forKey: .id); title = try c.decode(String.self, forKey: .title)
            state = try c.decode(String.self, forKey: .state); summary = try c.decode(String.self, forKey: .summary)
            from = (try? c.decodeIfPresent(Int.self, forKey: .from)) ?? nil   // bozuk sapak tüm yanıtı düşürmez
            left = (try? c.decodeIfPresent([String].self, forKey: .left)) ?? []   // bozuk liste de düşürmez
        }
    }
    public var topics: [Item]
    public var assign: [String: Int]   // "istek no" -> konu id
}

private let maxTextChars = 500
private let maxReplyChars = 300

/// `grouped`'dan sonraki istekler; tur sürerken (working) son istek henüz cevapsız olduğundan hariç.
public func groupableRequests(_ requests: [Request], grouped: Int, working: Bool) -> ArraySlice<Request> {
    let end = working ? requests.count - 1 : requests.count
    let start = max(grouped, 0)
    return start < end ? requests[start..<end] : []
}

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

/// Konunun gerçek istek numaraları; ardışık 3+ numara aralık olur: [1,2,13…20] → "#1,#2,#13-#20"
private func requestNumbers(_ nums: [Int]) -> String {
    var parts: [String] = [], run: [Int] = []
    func flush() { parts += run.count >= 3 ? ["#\(run[0])-#\(run[run.count - 1])"] : run.map { "#\($0)" }; run = [] }
    for n in Set(nums).sorted() {
        if let last = run.last, n != last + 1 { flush() }
        run.append(n)
    }
    flush()
    return parts.isEmpty ? "-" : parts.joined(separator: ",")
}

public func buildTopicPrompt(existing: [Topic], requests: [Request]) -> String {
    let fmt = DateFormatter()
    fmt.locale = Locale(identifier: "en_US_POSIX")
    fmt.timeZone = .current
    fmt.dateFormat = "HH:mm"

    let topicLines = existing.isEmpty ? "(yok)" : existing.map { t in
        "- id \(t.id) | \(t.title) | durum: \(t.state) | istekler: \(requestNumbers(t.requests)) | özet: \(t.summary) | sapak: \(t.from.map(String.init) ?? "-") | kalan: \(t.left.isEmpty ? "-" : t.left.joined(separator: "; "))"
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
    - Şema: {"topics":[{"id":1,"title":"…","state":"active|open|done","summary":"…","from":null,"left":[]}],"assign":{"12":1}}
    - Mevcut tüm konuları gerektiği gibi güncelleyerek döndür. Yeni bir konu gerekirse id değerini mevcut en büyük id'den büyük ver.
    - Her yeni istek numarasını "assign" içinde tam olarak bir konuya ata (anahtar istek numarası, değer konu id'si). Eski istekleri assign'a yazma.
    - Başlıklar en fazla 6 kelime, özetler en fazla 3 cümle olsun ve Türkçe yazılsın.
    - Bir konunun işi bitmişse "done" yap. Claude işi bitirdiğini ya da düzelttiğini bildirdikten sonra kullanıcı itiraz etmeden başka konuya geçtiyse konu bitmiş sayılır.
    - "open" yalnızca açıkça yarım kalan, bir şey bekleyen ya da sonra dönüleceği söylenen iş içindir.
    - Mevcut "open" konuları yeni isteklere göre yeniden değerlendir; sonradan bittiği anlaşılıyorsa "done" yap.
    - "from": konu başka bir konu bitmeden ondan sapılarak açıldıysa o konunun id'si; önceki iş bittikten sonra ya da ana iş olarak başladıysa null. Mevcut from değerlerini gerekmedikçe değiştirme. Sapak konunun işi bittiyse ya da ana konuya bağlandıysa onu "done" yap.
    - "left": konu "open" ise yarım kalan işleri en fazla 3 kısa madde olarak yaz (her biri en fazla 10 kelime); değilse boş liste.
    - Başlıklar gereksiz yere değiştirilmesin.
    - \(dataNotice)

    Mevcut konular:
    \(dataBlock(topicLines))

    Yeni istekler:
    \(dataBlock(reqLines))
    """
}

/// Model metni arayüzde gösterilir ve paylaşılır: tek satır, kontrol/biçim karakteri yok, uzunluk sınırlı
func oneLine(_ s: String, max: Int) -> String {
    let kept = s.unicodeScalars.filter { $0.properties.isWhitespace || !CharacterSet.controlCharacters.contains($0) }
    return String(String(String.UnicodeScalarView(kept)).split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(max))
}

public func parseTopicResponse(_ output: String) -> TopicResponse? {
    guard let a = output.firstIndex(of: "{"), let b = output.lastIndex(of: "}"), a < b,
          var r = try? JSONDecoder().decode(TopicResponse.self, from: Data(output[a...b].utf8)) else { return nil }
    for i in r.topics.indices {
        r.topics[i].title = oneLine(r.topics[i].title, max: 80)
        r.topics[i].summary = oneLine(r.topics[i].summary, max: 500)
        r.topics[i].left = Array(r.topics[i].left.map { oneLine($0, max: 80) }.filter { !$0.isEmpty }.prefix(3))
    }
    return r
}

public func mergeTopics(existing: [Topic], response: TopicResponse, newRequests: [Request]) -> [Topic]? {
    guard !response.topics.contains(where: { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return nil }

    var byId: [Int: Topic] = [:]
    for t in existing { byId[t.id] = t }
    for item in response.topics {
        var t = byId[item.id] ?? Topic(id: item.id, title: "", state: "open", summary: "", requests: [])
        t.title = item.title; t.state = item.state; t.summary = item.summary; t.from = item.from; t.left = item.left
        byId[item.id] = t
    }
    for r in newRequests {
        guard let id = response.assign[String(r.index)], byId[id] != nil else { return nil }
        byId[id]?.requests.append(r.index)
        byId[id]?.closedByUser = false   // yeni istek kapatmayı geçersiz kılar
    }

    var topics = byId.values.filter { !$0.requests.isEmpty }
    let maxIndex = topics.compactMap { $0.requests.max() }.max()
    for i in topics.indices {
        let isLast = topics[i].requests.max() == maxIndex
        topics[i].state = topics[i].closedByUser ? "done" : isLast ? "active" : (topics[i].state == "done" ? "done" : "open")
        if topics[i].state != "open" { topics[i].left = [] }
    }
    topics.sort { ($0.requests.min() ?? 0) < ($1.requests.min() ?? 0) }
    // geçerli sapak: listede var, kendisi değil, ondan önce başlamış
    let start = Dictionary(uniqueKeysWithValues: topics.map { ($0.id, $0.requests.min() ?? 0) })
    for i in topics.indices {
        topics[i].from = validFrom(topics[i], starts: start)
    }
    return topics
}

/// Geçerli sapak: listede var, kendisi değil, ondan önce başlamış. starts: konu id -> ilk istek no.
func validFrom(_ t: Topic, starts: [Int: Int]) -> Int? {
    guard let f = t.from, f != t.id, let s = starts[f], s < (t.requests.min() ?? 0) else { return nil }
    return f
}

public func loadTopicFile(_ url: URL) -> TopicFile? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
    return (try? dec.decode(TopicFile.self, from: data)).flatMap { $0.version == TopicFile.currentVersion ? $0 : nil }
}

public func saveTopicFile(_ file: TopicFile, to url: URL) throws {
    let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
    try writeAtomically(try enc.encode(file), to: url)
}

/// Önce 0600 ile geçici dosya, sonra rename: izin penceresi ve yarım yazım olmaz
public func writeAtomically(_ data: Data, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700])
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
    /// üst üste başarısız gruplama sayısı
    public var failures: Int
    public init(id: String, ungrouped: Int, state: SessionState, alive: Bool, lastRunAt: Date?, lastRunLeftBacklog: Bool, failures: Int = 0) {
        self.id = id; self.ungrouped = ungrouped; self.state = state; self.alive = alive
        self.lastRunAt = lastRunAt; self.lastRunLeftBacklog = lastRunLeftBacklog; self.failures = failures
    }
}

/// Sıradaki gruplama işi: seçili session uygunsa o, yoksa uygun ilk aday (adaylar görüntü sırasıyla gelir).
/// Başarısızlıkta bekleme her seferinde iki katına çıkar (en fazla 1 saat).
public func nextGroupingJob(_ candidates: [GroupingCandidate], selected: String?, now: Date, gap: TimeInterval = 120) -> String? {
    let eligible = candidates.filter { c in
        let wait = min(gap * pow(2, Double(c.failures)), 3600)
        return c.ungrouped > 0
            && (c.id == selected || (c.alive && c.state != .working))
            && ((c.failures == 0 && c.lastRunLeftBacklog) || (c.lastRunAt.map { now.timeIntervalSince($0) >= wait } ?? true))
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
