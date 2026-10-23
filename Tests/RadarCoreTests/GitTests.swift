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
