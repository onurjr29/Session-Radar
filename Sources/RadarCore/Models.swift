import Foundation

public enum SessionState: String, Codable, Sendable { case working, waiting, turnDone, problem, closed }

public struct HookEvent: Codable, Equatable, Sendable {
    public var ts: Double
    public var event: String
    public var sessionId: String
    public var cwd: String?
    public var transcriptPath: String?
    public var tool: String?
    public var target: String?
    public var notificationType: String?
    public var message: String?
    public var endsWithQuestion: Bool?
    public var backgroundTasks: Int?
    /// SessionStart: startup | resume | clear | compact
    public var source: String?
}

public struct TodoItem: Codable, Equatable, Sendable { public var text: String; public var done: Bool }

public struct SessionStatus: Codable, Equatable, Sendable {
    public var task: String?
    public var why: String?
    public var phase: String?
    public var next: String?
    public var todo: [TodoItem]?
    public var problems: [String]?

    public init(task: String? = nil, why: String? = nil, phase: String? = nil, next: String? = nil,
                todo: [TodoItem]? = nil, problems: [String]? = nil) {
        self.task = task; self.why = why; self.phase = phase; self.next = next
        self.todo = todo; self.problems = problems
    }
}

public struct AgentEntry: Codable, Equatable, Sendable {
    public var id: String?
    public var pid: Int32?
    public var sessionId: String
    public var name: String?
    public var cwd: String
    public var kind: String
    public var startedAt: Double?
    public var status: String?
    public var state: String?
}

public struct Progress: Equatable, Sendable { public var done: Int; public var total: Int }

public struct SessionSnapshot: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var cwd: String
    public var repoName: String?
    public var repoKey: String?
    /// checkout'un kökü (git toplevel)
    public var repoRoot: String?
    public var branch: String?
    public var state: SessionState
    public var note: String?
    public var task: String?
    public var action: String?
    public var progress: Progress?
    public var status: SessionStatus?
    public var pendingFiles: Set<String>
    public var transcriptPath: String?
    public var updatedAt: Date
    public var currentTopic: String? = nil
    public var openTopics: Int = 0
}

public struct RadarPaths: Sendable {
    public let root: URL
    public init(root: URL) { self.root = root }

    public static func fromEnvironment(_ env: [String: String] = ProcessInfo.processInfo.environment) -> RadarPaths {
        if let home = env["SESSION_RADAR_HOME"], !home.isEmpty {
            return RadarPaths(root: URL(fileURLWithPath: home))
        }
        return RadarPaths(root: FileManager.default.homeDirectoryForCurrentUser.appending(path: ".session-radar"))
    }

    public var eventsDir: URL { root.appending(path: "events") }
    public var statusDir: URL { root.appending(path: "status") }
    public var askDir: URL { root.appending(path: "ask") }
    public var topicsDir: URL { root.appending(path: "topics") }
    public func eventLog(_ sessionId: String) -> URL { eventsDir.appending(path: "\(sessionId).jsonl") }
    public func statusFile(_ sessionId: String) -> URL { statusDir.appending(path: "\(sessionId).json") }
    public func topicFile(_ sessionId: String) -> URL { topicsDir.appending(path: "\(sessionId).json") }

    /// Veri klasörlerini yalnızca kullanıcıya açık (0700) oluşturur; önceden var olanları da daraltır.
    public func prepareDirectories() throws {
        let fm = FileManager.default
        for dir in [root, eventsDir, statusDir, askDir, topicsDir] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        }
    }

    public func isInternal(cwd: String) -> Bool {
        let r = root.standardizedFileURL.path
        let c = URL(fileURLWithPath: cwd).standardizedFileURL.path
        return c == r || c.hasPrefix(r + "/")
    }
}
