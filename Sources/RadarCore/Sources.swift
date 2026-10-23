import Foundation

public func parseAgents(_ data: Data) -> [AgentEntry] {
    (try? JSONDecoder().decode([AgentEntry].self, from: data)) ?? []
}

public func loadStatus(_ url: URL) -> SessionStatus? {
    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
    guard size <= 64 * 1024, let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(SessionStatus.self, from: data)
}

public struct TranscriptInfo: Equatable, Sendable {
    public var aiTitle: String?
    public var lastPrompt: String?
    public var lastAction: String?
    public var dialogue: [String]
}

public func readTranscriptTail(_ url: URL, maxBytes: Int = 512_000) -> TranscriptInfo {
    var info = TranscriptInfo(aiTitle: nil, lastPrompt: nil, lastAction: nil, dialogue: [])
    guard let fh = try? FileHandle(forReadingFrom: url) else { return info }
    defer { try? fh.close() }
    guard let size = try? fh.seekToEnd() else { return info }
    let start = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
    guard (try? fh.seek(toOffset: start)) != nil, let data = try? fh.readToEnd() else { return info }

    // önce satırlara böl, sonra her satırı ayrı çöz; ortadan başlandıysa ilk satır yarımdır
    var lines = data.split(separator: 0x0A, omittingEmptySubsequences: true)
    if start > 0, !lines.isEmpty { lines.removeFirst() }

    var lastUserPrompt: String?
    for line in lines {
        guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let type = obj["type"] as? String else { continue }
        let message = obj["message"] as? [String: Any]
        switch type {
        case "ai-title":
            info.aiTitle = obj["aiTitle"] as? String
        case "last-prompt":
            info.lastPrompt = obj["lastPrompt"] as? String
        case "user":
            guard obj["isMeta"] as? Bool != true, let text = message?["content"] as? String else { continue }
            lastUserPrompt = text
            info.dialogue.append("Kullanıcı: " + String(text.prefix(2000)))
        case "assistant":
            guard let blocks = message?["content"] as? [[String: Any]] else { continue }
            let text = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
            if !text.isEmpty { info.dialogue.append("Claude: " + String(text.prefix(2000))) }
            if let tool = blocks.last(where: { $0["type"] as? String == "tool_use" }), let name = tool["name"] as? String {
                let input = tool["input"] as? [String: Any]
                info.lastAction = describeAction(tool: name, target: (input?["file_path"] ?? input?["command"]) as? String)
            } else {
                info.lastAction = nil
            }
        default: continue
        }
    }
    if info.lastPrompt == nil { info.lastPrompt = lastUserPrompt }
    return info
}

public func findTranscript(sessionId: String, projectsDir: URL) -> URL? {
    let fm = FileManager.default
    guard let dirs = try? fm.contentsOfDirectory(at: projectsDir, includingPropertiesForKeys: nil) else { return nil }
    return dirs.map { $0.appending(path: "\(sessionId).jsonl") }.first { fm.fileExists(atPath: $0.path) }
}
