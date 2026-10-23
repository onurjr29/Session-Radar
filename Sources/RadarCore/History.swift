import Foundation

public struct Request: Codable, Equatable, Sendable {
    public var index: Int
    public var text: String
    public var at: Date?
    public var reply: String?
    public init(index: Int, text: String, at: Date?, reply: String?) {
        self.index = index; self.text = text; self.at = at; self.reply = reply
    }
}

public struct HistoryCursor: Codable, Equatable, Sendable {
    public var offset: UInt64 = 0
    public var nextIndex: Int = 1
    public init() {}
}

public struct HistoryRead: Equatable, Sendable {
    public var requests: [Request]
    /// İlk yeni istekten önce görülen son Claude metni (bir önceki isteğe ait)
    public var trailingReply: String?
    public var cursor: HistoryCursor
    /// Dosya cursor.offset'ten küçükse true; cursor sıfırlanıp dosya baştan okunur
    public var truncated: Bool
}

private let noisyFlags = ["isMeta", "isCompactSummary", "isVisibleInTranscriptOnly", "isSidechain"]

private func isRequestText(_ text: String) -> Bool {
    let t = text.drop(while: \.isWhitespace)
    if t.hasPrefix("<pasted_content") { return true }
    return !t.hasPrefix("<") && !t.hasPrefix("[Request interrupted")
}

// ponytail: uygulama her açılışta transcript'i baştan tarar; çok büyük dosyalarda cursor+istekler diske yazılabilir
public func readRequests(_ url: URL, from cursor: HistoryCursor, chunkSize: Int = 4 << 20) -> HistoryRead {
    var cur = cursor
    var truncated = false
    var out = HistoryRead(requests: [], trailingReply: nil, cursor: cur, truncated: false)
    guard let fh = try? FileHandle(forReadingFrom: url) else { return out }
    defer { try? fh.close() }
    if let size = try? fh.seekToEnd(), size < cur.offset { cur = HistoryCursor(); truncated = true }
    guard (try? fh.seek(toOffset: cur.offset)) != nil else { return out }

    let userKey = Data(#""type":"user""#.utf8), asstKey = Data(#""type":"assistant""#.utf8), textKey = Data(#""type":"text""#.utf8)
    let isoFrac = ISO8601DateFormatter(); isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let iso = ISO8601DateFormatter()
    var requests: [Request] = []
    var pending: String?       // bir sonraki istekten önce görülen son Claude metni
    var trailing: String?
    var carry = Data()

    func handle(_ line: Data) {
        let isUser = line.range(of: userKey) != nil
        let isAsst = !isUser && line.range(of: asstKey) != nil && line.range(of: textKey) != nil
        guard isUser || isAsst,
              let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let message = obj["message"] as? [String: Any] else { return }
        if obj["isSidechain"] as? Bool == true { return }
        if isAsst {
            guard obj["type"] as? String == "assistant", let blocks = message["content"] as? [[String: Any]] else { return }
            let text = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
            if !text.isEmpty { pending = String(text.prefix(2000)) }
            return
        }
        guard obj["type"] as? String == "user", let text = message["content"] as? String,
              !noisyFlags.contains(where: { obj[$0] as? Bool == true }), isRequestText(text) else { return }
        if requests.isEmpty { trailing = pending } else { requests[requests.count - 1].reply = pending }
        pending = nil
        let at = (obj["timestamp"] as? String).flatMap { isoFrac.date(from: $0) ?? iso.date(from: $0) }
        requests.append(Request(index: cur.nextIndex, text: String(text.prefix(2000)), at: at, reply: nil))
        cur.nextIndex += 1
    }

    while true {
        var eof = false
        autoreleasepool {
            guard let chunk = try? fh.read(upToCount: max(chunkSize, 1)), !chunk.isEmpty else { eof = true; return }
            carry.append(chunk)
            guard let nl = carry.lastIndex(of: 0x0A) else { return }
            let body = carry[carry.startIndex...nl]
            for line in body.split(separator: 0x0A, omittingEmptySubsequences: true) { handle(Data(line)) }
            cur.offset += UInt64(body.count)
            carry = Data(carry[(nl + 1)...])
        }
        if eof { break }
    }
    if !requests.isEmpty { requests[requests.count - 1].reply = pending } else { trailing = pending }
    out = HistoryRead(requests: requests, trailingReply: trailing, cursor: cur, truncated: truncated)
    return out
}
