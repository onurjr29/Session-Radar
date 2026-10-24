import Foundation

/// Remote URL'ini karşılaştırılabilir biçime çevirir; kimlik bilgisi ve port atılır.
public func normalizeRemote(_ url: String) -> String {
    var s = url.trimmingCharacters(in: .whitespacesAndNewlines)
    let hasScheme = s.range(of: "://").map { s.removeSubrange(s.startIndex..<$0.upperBound) } != nil
    let firstSlash = s.firstIndex(of: "/") ?? s.endIndex
    // user:parola@ (yalnızca host kısmında)
    if let at = s[..<firstSlash].lastIndex(of: "@") { s.removeSubrange(s.startIndex...at) }
    let slash = s.firstIndex(of: "/") ?? s.endIndex
    if let colon = s[..<slash].firstIndex(of: ":") {
        if hasScheme {
            s.removeSubrange(colon..<slash)   // :port
        } else {
            s.replaceSubrange(colon...colon, with: "/")   // scp biçimi host:org/repo
        }
    }
    while s.hasSuffix("/") { s.removeLast() }
    if s.hasSuffix(".git") { s.removeLast(4) }
    while s.hasSuffix("/") { s.removeLast() }
    return s.lowercased()
}

public func parseNulPaths(_ data: Data, porcelain: Bool) -> Set<String> {
    let fields = data.split(separator: 0, omittingEmptySubsequences: true).map { String(decoding: $0, as: UTF8.self) }
    var out = Set<String>()
    var i = 0
    while i < fields.count {
        let f = fields[i]
        i += 1
        guard porcelain else { out.insert(f); continue }
        guard f.count > 3 else { continue }
        out.insert(String(f.dropFirst(3)))
        if f.first == "R" || f.first == "C" { i += 1 }   // eski yolu atla
    }
    return out
}

public struct RepoInfo: Equatable, Sendable {
    public var toplevel: String
    public var key: String
    public var name: String
    public var branch: String?
    public var pending: Set<String>
}

private func run(_ git: String, _ args: [String], cwd: String, environment extra: [String: String] = [:],
                 discardStderr: Bool = false, timeout: TimeInterval = 10) -> Data? {
    // arka plan poller'ı index.lock almasın
    let env = ProcessInfo.processInfo.environment.merging(["GIT_OPTIONAL_LOCKS": "0"]) { $1 }.merging(extra) { $1 }
    guard let r = runProcess(git, ["-C", cwd] + args, environment: env, discardStderr: discardStderr, timeout: timeout),
          r.status == 0 else { return nil }
    return r.stdout
}

public func repoInfo(cwd: String, git: String = "/usr/bin/git") -> RepoInfo? {
    func text(_ args: [String]) -> String? {
        run(git, args, cwd: cwd).map { String(decoding: $0, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    guard let top = text(["rev-parse", "--show-toplevel"]), !top.isEmpty else { return nil }
    let key = text(["remote", "get-url", "origin"]).flatMap { $0.isEmpty ? nil : normalizeRemote($0) } ?? "local:" + top
    let name = key.split(separator: "/").last.map(String.init) ?? key
    let branch = text(["branch", "--show-current"]).flatMap { $0.isEmpty ? nil : $0 }
    var pending = Set<String>()
    if let d = run(git, ["-c", "core.quotePath=false", "status", "--porcelain", "-uall", "-z"], cwd: cwd) {
        pending.formUnion(parseNulPaths(d, porcelain: true))
    }
    let unpushed = run(git, ["diff", "--name-only", "-z", "@{upstream}...HEAD"], cwd: cwd)
        ?? run(git, ["diff", "--name-only", "-z", "origin/HEAD...HEAD"], cwd: cwd)
    if let d = unpushed { pending.formUnion(parseNulPaths(d, porcelain: false)) }
    return RepoInfo(toplevel: top, key: key, name: name, branch: branch, pending: pending)
}

public struct IncomingPush: Equatable, Sendable {
    public var upstream: String
    public var head: String
    public var count: Int
    public var authors: [String]
    public var latestAt: Date
    public var files: [String]
}

/// Ölü bağlantıda ssh ve https kendini bırakır; stderr'i tutan yardımcı da timeout'tan sonra bekletmez.
public func fetchUpstream(cwd: String, git: String = "/usr/bin/git", timeout: TimeInterval = 30) -> Bool {
    run(git, ["fetch", "--quiet", "--no-tags", "--no-recurse-submodules"], cwd: cwd,
        environment: ["GIT_TERMINAL_PROMPT": "0",
                      "GIT_SSH_COMMAND": "ssh -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=5 -o ServerAliveCountMax=2",
                      "GIT_HTTP_LOW_SPEED_LIMIT": "1000", "GIT_HTTP_LOW_SPEED_TIME": "10"],
        discardStderr: true, timeout: timeout) != nil
}

/// Upstream'de olup yerelde olmayan commit'ler; upstream yoksa, HEAD detached ise ya da yerel ileride ise nil.
public func incomingPush(cwd: String, git: String = "/usr/bin/git") -> IncomingPush? {
    func text(_ args: [String]) -> String? {
        run(git, args, cwd: cwd).map { String(decoding: $0, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    guard let upstream = text(["rev-parse", "--abbrev-ref", "@{upstream}"]), !upstream.isEmpty,
          run(git, ["merge-base", "--is-ancestor", "@{upstream}", "HEAD"], cwd: cwd) == nil,
          let head = text(["rev-parse", "@{upstream}"]), !head.isEmpty,
          let count = text(["rev-list", "--count", "HEAD..@{upstream}"]).flatMap(Int.init), count > 0,
          let at = text(["log", "-1", "--format=%ct", "@{upstream}"]).flatMap(TimeInterval.init)
    else { return nil }
    var authors: [String] = []
    for a in (text(["log", "--format=%an", "HEAD..@{upstream}"]) ?? "").split(separator: "\n").map(String.init)
    where !authors.contains(a) { authors.append(a) }
    let files = run(git, ["-c", "core.quotePath=false", "diff", "--name-only", "-z", "HEAD...@{upstream}"], cwd: cwd)
        .map { parseNulPaths($0, porcelain: false).sorted() } ?? []
    return IncomingPush(upstream: upstream, head: head, count: count, authors: authors,
                        latestAt: Date(timeIntervalSince1970: at), files: files)
}

/// Var olmayan yolda (silinmiş dosya) en derin var olan atayı çözüp kalanı geri ekler.
private func resolveExisting(_ path: String) -> String {
    var url = URL(fileURLWithPath: path)
    var tail: [String] = []
    while !FileManager.default.fileExists(atPath: url.path), url.path != "/" {
        tail.insert(url.lastPathComponent, at: 0)
        url = url.deletingLastPathComponent()
    }
    return tail.reduce(url.resolvingSymlinksInPath()) { $0.appending(path: $1) }.path
}

public func pendingTouched(_ touched: Set<String>, repo: RepoInfo) -> Set<String> {
    let root = URL(fileURLWithPath: repo.toplevel).resolvingSymlinksInPath().path + "/"
    var rel = Set<String>()
    for t in touched {
        let p = resolveExisting(t)
        if p.hasPrefix(root) { rel.insert(String(p.dropFirst(root.count))) }
    }
    return rel.intersection(repo.pending)
}

public struct Conflict: Hashable, Sendable {
    public var a: String
    public var b: String
    public var files: [String]
    public var pairKey: String { "\(a)|\(b)" }
}

public func findConflicts(_ sessions: [SessionSnapshot]) -> [Conflict] {
    let s = sessions.filter { $0.repoKey != nil }.sorted { $0.id < $1.id }
    var out: [Conflict] = []
    for i in s.indices {
        for j in s.indices where j > i && s[i].repoKey == s[j].repoKey {
            // aynı checkout'ta kapanmış session'ın dosyaları ardılının dosyalarıdır; çakışma değil
            if let root = s[i].repoRoot, root == s[j].repoRoot, s[i].state == .closed || s[j].state == .closed { continue }
            let common = s[i].pendingFiles.intersection(s[j].pendingFiles)
            if !common.isEmpty { out.append(Conflict(a: s[i].id, b: s[j].id, files: common.sorted())) }
        }
    }
    return out
}
