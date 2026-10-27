import Foundation

/// Kullanıcının radardan kapattığı konu; Claude Code'a bir kez iletilir
public struct ClosedTopicNote: Codable, Equatable, Sendable {
    public var title: String
    public var left: [String]
    public init(title: String, left: [String]) { self.title = title; self.left = left }
}

/// Yalnızca "open" konuyu kapatır; konu yoksa ya da açık değilse nil.
public func closeTopic(_ topics: [Topic], id: Int) -> (topics: [Topic], note: ClosedTopicNote)? {
    guard let i = topics.firstIndex(where: { $0.id == id }), topics[i].state == "open" else { return nil }
    var out = topics
    let note = ClosedTopicNote(title: topics[i].title, left: topics[i].left)
    out[i].state = "done"; out[i].left = []; out[i].closedByUser = true
    return (out, note)
}

public func appendClosedNote(_ note: ClosedTopicNote, to url: URL) throws {
    let list = readJSON([ClosedTopicNote].self, from: url) ?? []
    try writeJSON(list + [note], to: url)
}

/// rename ile sahiplenme: uygulamanın sonradan yazdığı not ayrı dosyada kalır, iki hook aynı notu almaz
public func takeClosedNotes(_ url: URL) -> [ClosedTopicNote] {
    let mine = url.deletingLastPathComponent().appending(path: ".\(UUID().uuidString).taken")
    guard rename(url.path, mine.path) == 0 else { return [] }
    defer { try? FileManager.default.removeItem(at: mine) }
    return readJSON([ClosedTopicNote].self, from: mine) ?? []
}

public func closedNoteText(_ notes: [ClosedTopicNote]) -> String? {
    guard !notes.isEmpty else { return nil }
    return notes.map { n in
        let title = teamText(n.title, max: 80)
        if n.left.isEmpty { return "Session Radar: Kullanıcı \"\(title)\" konusunu radardan kapattı; bu konudaki yarım iş artık gerekmiyor." }
        let left = n.left.map { teamText($0, max: 80) }.joined(separator: "; ")
        return "Session Radar: Kullanıcı \"\(title)\" konusunu radardan kapattı; yarım kalan adımlar (\(left)) artık gerekmiyor."
    }.joined(separator: "\n")
}
