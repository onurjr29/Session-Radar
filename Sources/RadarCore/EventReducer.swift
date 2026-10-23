import Foundation

public struct Activity: Equatable, Sendable {
    public var state: SessionState = .turnDone
    public var action: String?
    public var note: String?
    public var touched: Set<String> = []
    public var lastEventAt: Double?
    public var lastEvent: String?
    public var ended = false
    public var cwd: String?
    public var transcriptPath: String?
    public init() {}
}

public func describeAction(tool: String, target: String?) -> String {
    guard let target else { return tool }
    switch tool {
    case "Edit", "Write", "MultiEdit", "NotebookEdit", "Read":
        return "\(tool) · \(URL(fileURLWithPath: target).lastPathComponent)"
    case "Bash": return "Bash · \(target)"
    default: return tool
    }
}

private let editTools: Set<String> = ["Edit", "Write", "MultiEdit", "NotebookEdit"]

public func apply(_ e: HookEvent, to a: inout Activity) {
    // radar'ın kendi dosyalarına dokunan tool olayları yok sayılır
    if let t = e.target, t.contains("/.session-radar/") { return }
    a.lastEventAt = e.ts
    a.lastEvent = e.event
    if let c = e.cwd { a.cwd = c }
    if let p = e.transcriptPath { a.transcriptPath = p }

    switch e.event {
    case "SessionStart":
        a.state = .turnDone; a.action = nil; a.note = nil
    case "UserPromptSubmit":
        a.state = .working; a.note = nil
    case "PreToolUse":
        if e.tool == "AskUserQuestion" {
            a.state = .waiting; a.note = e.target
        } else {
            a.state = .working; a.note = nil
            a.action = describeAction(tool: e.tool ?? "", target: e.target)
        }
    case "PostToolUse":
        if a.state == .waiting { a.state = .working; a.note = nil }
        if let tool = e.tool, editTools.contains(tool), let t = e.target, t.hasPrefix("/") { a.touched.insert(t) }
    case "Notification":
        switch e.notificationType {
        case "permission_prompt", "elicitation_dialog", "elicitation_url_dialog", "agent_needs_input":
            a.state = .waiting; a.note = e.message
        case "quota_auto_resume_stale", "quota_auto_resume_disabled":
            a.state = .problem; a.note = e.message
        case "quota_auto_resume_fired": a.state = .working
        case "agent_completed": a.state = .turnDone
        default: break
        }
    case "Stop":
        if (e.backgroundTasks ?? 0) > 0 {
            a.state = .working; a.action = "Arka plan işi bekleniyor"
        } else if e.endsWithQuestion == true {
            a.state = .waiting; a.note = e.message; a.action = nil
        } else {
            a.state = .turnDone; a.action = nil
        }
    case "StopFailure":
        a.state = .problem; a.note = "API hatası: " + (e.message ?? "")
    case "SessionEnd":
        a.ended = true; a.state = .closed; a.action = nil
    default: break
    }
}

public func reduceEvents(_ events: [HookEvent]) -> Activity {
    var a = Activity()
    for e in events { apply(e, to: &a) }
    return a
}

public func resolveState(activity: Activity?, agent: AgentEntry?, alive: Bool, status: SessionStatus?) -> (state: SessionState, note: String?) {
    if activity?.ended == true { return (.closed, nil) }
    if !alive {
        if let a = activity, a.state == .working || a.state == .waiting {
            return (.problem, "Session beklenmedik şekilde kapandı")
        }
        return (.closed, nil)
    }
    if let p = status?.problems, p.contains(where: { !$0.isEmpty }) {
        return (.problem, p.joined(separator: "; "))
    }
    if let a = activity { return (a.state, a.note) }
    guard let agent else { return (.turnDone, nil) }
    if agent.kind == "background" {
        switch agent.state {
        case "working": return (.working, nil)
        case "blocked": return (.waiting, nil)
        default: return (.turnDone, nil)
        }
    }
    return (agent.status == "busy" ? .working : .turnDone, nil)
}

public final class EventLogReader: @unchecked Sendable {
    private let paths: RadarPaths
    private var offsets: [String: UInt64] = [:]
    private let lock = NSLock()

    public init(paths: RadarPaths) { self.paths = paths }

    public func forget(_ sessionId: String) {
        lock.lock(); defer { lock.unlock() }
        offsets[sessionId] = nil
    }

    public func poll() -> [String: [HookEvent]] {
        lock.lock(); defer { lock.unlock() }
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-7 * 86400)
        guard let files = try? fm.contentsOfDirectory(
            at: paths.eventsDir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [:] }
        var out: [String: [HookEvent]] = [:]
        for url in files where url.pathExtension == "jsonl" {
            let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            guard let mtime, mtime >= cutoff else { continue }
            let sid = url.deletingPathExtension().lastPathComponent
            guard let h = try? FileHandle(forReadingFrom: url) else { continue }
            defer { try? h.close() }
            var offset = offsets[sid] ?? 0
            if let size = try? h.seekToEnd(), size < offset { offset = 0 }  // dosya kısaldıysa baştan oku
            guard (try? h.seek(toOffset: offset)) != nil,
                  let data = try? h.readToEnd(),
                  let lastNL = data.lastIndex(of: 0x0A) else { continue }
            offsets[sid] = offset + UInt64(lastNL - data.startIndex + 1)
            let dec = JSONDecoder()
            let events = data[data.startIndex...lastNL].split(separator: 0x0A)
                .compactMap { try? dec.decode(HookEvent.self, from: Data($0)) }
            if !events.isEmpty { out[sid] = events }
        }
        return out
    }
}
