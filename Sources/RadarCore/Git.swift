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

private func run(_ git: String, _ args: [String], cwd: String) -> Data? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: git)
    p.arguments = ["-C", cwd] + args
    let out = Pipe()
    p.standardOutput = out
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return nil }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return p.terminationStatus == 0 ? data : nil
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
    if let d = run(git, ["-c", "core.quotePath=false", "status", "--porcelain", "-z"], cwd: cwd) {
        pending.formUnion(parseNulPaths(d, porcelain: true))
    }
    let unpushed = run(git, ["diff", "--name-only", "-z", "@{upstream}...HEAD"], cwd: cwd)
        ?? run(git, ["diff", "--name-only", "-z", "origin/HEAD...HEAD"], cwd: cwd)
    if let d = unpushed { pending.formUnion(parseNulPaths(d, porcelain: false)) }
    return RepoInfo(toplevel: top, key: key, name: name, branch: branch, pending: pending)
}

public func pendingTouched(_ touched: Set<String>, repo: RepoInfo) -> Set<String> {
    let root = URL(fileURLWithPath: repo.toplevel).resolvingSymlinksInPath().path + "/"
    var rel = Set<String>()
    for t in touched {
        let p = URL(fileURLWithPath: t).resolvingSymlinksInPath().path
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
            let common = s[i].pendingFiles.intersection(s[j].pendingFiles)
            if !common.isEmpty { out.append(Conflict(a: s[i].id, b: s[j].id, files: common.sorted())) }
        }
    }
    return out
}
