import Testing
import Foundation
@testable import RadarCore

@discardableResult
private func sh(_ args: [String], in dir: URL) throws -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    p.arguments = args
    p.currentDirectoryURL = dir
    let out = Pipe()
    p.standardOutput = out
    p.standardError = FileHandle.nullDevice
    try p.run()
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(decoding: data, as: UTF8.self)
}

private func uniqueDir(_ label: String) throws -> URL {
    let d = FileManager.default.temporaryDirectory.appending(path: "radar-\(label)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}

private func configure(_ dir: URL) throws {
    try sh(["config", "user.email", "t@example.com"], in: dir)
    try sh(["config", "user.name", "Test"], in: dir)
}

private func tempGitRepo() throws -> URL {
    let dir = try uniqueDir("repo")
    try sh(["init", "-q", "-b", "main"], in: dir)
    try configure(dir)
    try "a".write(to: dir.appending(path: "a.txt"), atomically: true, encoding: .utf8)
    try sh(["add", "-A"], in: dir)
    try sh(["commit", "-q", "-m", "init"], in: dir)
    return dir
}

private func tempClonedRepo() throws -> (clone: URL, bare: URL) {
    let bare = try uniqueDir("bare")
    try sh(["init", "-q", "--bare", "-b", "main"], in: bare)
    let clone = try uniqueDir("clone")
    try sh(["init", "-q", "-b", "main"], in: clone)
    try configure(clone)
    try sh(["remote", "add", "origin", bare.path], in: clone)
    try "b".write(to: clone.appending(path: "b.txt"), atomically: true, encoding: .utf8)
    try sh(["add", "-A"], in: clone)
    try sh(["commit", "-q", "-m", "b"], in: clone)
    try sh(["push", "-q", "-u", "origin", "main"], in: clone)
    try "c".write(to: clone.appending(path: "c.txt"), atomically: true, encoding: .utf8)
    try sh(["add", "-A"], in: clone)
    try sh(["commit", "-q", "-m", "c"], in: clone)
    return (clone, bare)
}

@Test func normalizeRemoteForms() {
    #expect(normalizeRemote("git@github.com:Org/Repo.git") == "github.com/org/repo")
    #expect(normalizeRemote("https://user:tok@github.com/org/repo/") == "github.com/org/repo")
    #expect(normalizeRemote("ssh://git@github.com:22/org/repo.git") == "github.com/org/repo")
    #expect(normalizeRemote("/srv/git/repo.git") == "/srv/git/repo")
}

@Test func parsePorcelainHandlesRenameAndTurkish() {
    let d = Data(" M src/a.swift\u{0}R  yeni.swift\u{0}eski.swift\u{0}?? çalışma notu.txt\u{0}".utf8)
    #expect(parseNulPaths(d, porcelain: true) == ["src/a.swift", "yeni.swift", "çalışma notu.txt"])
}

@Test func repoInfoPendingIncludesDirtyAndUntracked() throws {
    let dir = try tempGitRepo()
    try "x".write(to: dir.appending(path: "a.txt"), atomically: true, encoding: .utf8)
    try "y".write(to: dir.appending(path: "çalışma.txt"), atomically: true, encoding: .utf8)
    let info = try #require(repoInfo(cwd: dir.path))
    #expect(info.pending == ["a.txt", "çalışma.txt"] && info.branch == "main" && info.key.hasPrefix("local:"))
    #expect(pendingTouched([dir.path + "/a.txt", "/baska/yer.txt"], repo: info) == ["a.txt"])
}

@Test func repoInfoPendingIncludesUnpushedNotPushed() throws {
    let (clone, bare) = try tempClonedRepo()
    let info = try #require(repoInfo(cwd: clone.path))
    #expect(info.pending.contains("c.txt") && !info.pending.contains("b.txt"))
    #expect(info.key == normalizeRemote(bare.path))
}

@Test func conflictsOnlyWithinSameRepo() {
    func s(_ id: String, _ key: String?, _ f: Set<String>) -> SessionSnapshot {
        SessionSnapshot(id: id, name: id, cwd: "/", repoName: nil, repoKey: key, branch: nil, state: .working,
                        note: nil, task: nil, action: nil, progress: nil, status: nil, pendingFiles: f,
                        transcriptPath: nil, updatedAt: Date(timeIntervalSince1970: 0))
    }
    let c = findConflicts([s("S1", "k", ["a", "b"]), s("S2", "k", ["b", "c"]), s("S3", "k2", ["b"]), s("S4", nil, ["b"])])
    #expect(c == [Conflict(a: "S1", b: "S2", files: ["b"])])
}

@Test func untrackedDirectoryListsFiles() throws {
    let dir = try tempGitRepo()
    try FileManager.default.createDirectory(at: dir.appending(path: "yeni"), withIntermediateDirectories: true)
    try "x".write(to: dir.appending(path: "yeni/x.swift"), atomically: true, encoding: .utf8)
    let info = try #require(repoInfo(cwd: dir.path))
    #expect(info.pending.contains("yeni/x.swift"))
}

@Test func deletedFileStillMatchesTouched() throws {
    let dir = try tempGitRepo()
    try FileManager.default.removeItem(at: dir.appending(path: "a.txt"))
    let info = try #require(repoInfo(cwd: dir.path))
    #expect(pendingTouched([dir.path + "/a.txt"], repo: info) == ["a.txt"])
}

@Test func closedSessionDoesNotConflictWithSuccessorInSameCheckout() {
    func s(_ id: String, _ root: String, _ st: SessionState) -> SessionSnapshot {
        SessionSnapshot(id: id, name: id, cwd: "/", repoName: nil, repoKey: "k", repoRoot: root, branch: nil, state: st,
                        note: nil, task: nil, action: nil, progress: nil, status: nil, pendingFiles: ["a"],
                        transcriptPath: nil, updatedAt: Date(timeIntervalSince1970: 0))
    }
    #expect(findConflicts([s("A", "/r", .closed), s("B", "/r", .working)]).isEmpty)
    #expect(findConflicts([s("A", "/r", .turnDone), s("B", "/r", .working)]).map(\.pairKey) == ["A|B"])
    #expect(findConflicts([s("A", "/r1", .closed), s("B", "/r2", .working)]).map(\.pairKey) == ["A|B"])
}

/// Bare remote + iki klon; B'nin yazarı "Anıl". A, B'nin push'unu henüz görmedi.
private func remotePair() throws -> (a: URL, b: URL) {
    let bare = try uniqueDir("bare")
    try sh(["init", "-q", "--bare", "-b", "main"], in: bare)
    let a = try uniqueDir("a")
    try sh(["init", "-q", "-b", "main"], in: a)
    try configure(a)
    try sh(["remote", "add", "origin", bare.path], in: a)
    try "a".write(to: a.appending(path: "a.txt"), atomically: true, encoding: .utf8)
    try sh(["add", "-A"], in: a)
    try sh(["commit", "-q", "-m", "init"], in: a)
    try sh(["push", "-q", "-u", "origin", "main"], in: a)
    let b = try uniqueDir("b")
    try sh(["clone", "-q", bare.path, b.path], in: b)
    try sh(["config", "user.email", "b@example.com"], in: b)
    try sh(["config", "user.name", "Anıl"], in: b)
    return (a, b)
}

private func commitFile(_ name: String, in dir: URL) throws {
    try name.write(to: dir.appending(path: name), atomically: true, encoding: .utf8)
    try sh(["add", "-A"], in: dir)
    try sh(["commit", "-q", "-m", name], in: dir)
}

@Test func incomingDetectsRemoteCommitsAndAuthors() throws {
    let (a, b) = try remotePair()
    try commitFile("b.txt", in: b)
    try sh(["push", "-q"], in: b)
    #expect(fetchUpstream(cwd: a.path))
    let p = try #require(incomingPush(cwd: a.path))
    #expect(p.upstream == "origin/main")
    #expect(p.count == 1)
    #expect(p.authors == ["Anıl"])
    #expect(p.files == ["b.txt"])
    #expect(p.head.count == 40)
}

@Test func noIncomingWhenUpToDateOrOnlyAhead() throws {
    let (a, b) = try remotePair()
    try commitFile("b.txt", in: b)
    try sh(["push", "-q"], in: b)
    #expect(fetchUpstream(cwd: a.path))
    try sh(["pull", "-q", "--ff-only"], in: a)
    #expect(incomingPush(cwd: a.path) == nil)
    try commitFile("local.txt", in: a)
    #expect(incomingPush(cwd: a.path) == nil)
}

@Test func noIncomingWithoutUpstreamOrDetached() throws {
    let (a, b) = try remotePair()
    try commitFile("b.txt", in: b)
    try sh(["push", "-q"], in: b)
    #expect(fetchUpstream(cwd: a.path))
    try sh(["checkout", "-q", "--detach"], in: a)
    #expect(incomingPush(cwd: a.path) == nil)
    try sh(["checkout", "-q", "-b", "yeni"], in: a)
    #expect(incomingPush(cwd: a.path) == nil)
}

@Test func fetchFailsOnUnreachableRemote() throws {
    let dir = try tempGitRepo()
    try sh(["remote", "add", "origin", "/nonexistent/x.git"], in: dir)
    #expect(!fetchUpstream(cwd: dir.path, timeout: 10))
}

/// Takılan git'in hayatta kalan yardımcısı stderr'i tutsa da fetch süre sınırında döner.
/// terminate() süreç grubunu öldürür; yardımcı SIGTERM'i yok sayarak (ya da grubundan çıkarak) hayatta kalır.
@Test(.timeLimit(.minutes(1))) func fetchSetsNetworkLimitsAndIgnoresLingeringHelper() throws {
    let dir = try uniqueDir("fakegit")
    let fake = dir.appending(path: "git")
    try """
    #!/bin/sh
    echo "$GIT_SSH_COMMAND|$GIT_HTTP_LOW_SPEED_LIMIT|$GIT_HTTP_LOW_SPEED_TIME" > "$(dirname "$0")/env.txt"
    (trap '' TERM; exec sleep 20) >/dev/null &
    exec sleep 20
    """.write(to: fake, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)
    let start = Date()
    #expect(!fetchUpstream(cwd: dir.path, git: fake.path, timeout: 1))
    #expect(Date().timeIntervalSince(start) < 10)
    let env = try String(contentsOf: dir.appending(path: "env.txt"), encoding: .utf8)
    #expect(env == "ssh -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=5 -o ServerAliveCountMax=2|1000|10\n")
}
