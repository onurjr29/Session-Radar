import Testing
import Foundation
@testable import RadarCore

private func executableScript(_ body: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "fake-\(UUID().uuidString).sh")
    try body.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url
}

@Test func resolveClaudeFindsLocalBinWithBarePath() {
    let p = resolveClaudePath(home: "/h", env: ["PATH": "/usr/bin:/bin"], isExecutable: { $0 == "/h/.local/bin/claude" }, shellLookup: { nil })
    #expect(p == "/h/.local/bin/claude")
    #expect(resolveClaudePath(home: "/h", env: [:], isExecutable: { _ in false }, shellLookup: { nil }) == nil)
}
@Test func askPromptKeepsNewestDialogue() {
    let dialogue = (0..<100).map { "Kullanıcı: mesaj \($0) " + String(repeating: "x", count: 500) }
    let p = buildAskPrompt(question: "Ne yapıyordun?", status: SessionStatus(task: "Login"), dialogue: dialogue, maxDialogueChars: 5_000)
    #expect(p.contains("Ne yapıyordun?") && p.contains("Login") && p.contains("mesaj 99") && !p.contains("mesaj 0 "))
}
@Test func runAskStripsApiKeyAndUsesAskDir() async throws {
    let paths = RadarPaths(root: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
    let fake = try executableScript("""
    #!/bin/sh
    [ -n "$ANTHROPIC_API_KEY" ] && { echo LEAK; exit 3; }
    echo "args:$*"; echo "pwd:$(pwd -P)"; cat
    """)
    setenv("ANTHROPIC_API_KEY", "sk-test", 1); defer { unsetenv("ANTHROPIC_API_KEY") }
    let out = try await runAsk(prompt: "MERHABA", claudePath: fake.path, paths: paths)
    #expect(!out.contains("LEAK") && out.contains("-p --model haiku") && out.contains("--no-session-persistence") && out.contains("MERHABA"))
    // resolvingSymlinksInPath /private önekini atar; pwd -P atmaz, o yüzden realpath
    #expect(out.contains("pwd:" + String(cString: realpath(paths.askDir.path, nil)!)))
}
@Test func runAskSurfacesFailure() async throws {
    let fake = try executableScript("#!/bin/sh\necho boom >&2\nexit 2\n")
    let paths = RadarPaths(root: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
    await #expect(throws: AskError.failed("boom")) { try await runAsk(prompt: "x", claudePath: fake.path, paths: paths) }
}
