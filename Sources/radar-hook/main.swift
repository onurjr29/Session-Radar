import Foundation
import RadarCore

// Claude Code hook ortamına kendi pid'ini CLAUDE_PID olarak koyar; eski sürümlerde ebeveyn süreç
let pid = ProcessInfo.processInfo.environment["CLAUDE_PID"].flatMap { Int32($0) } ?? getppid()
let out = runHook(stdin: FileHandle.standardInput.readDataToEndOfFile(),
                  paths: .fromEnvironment(), now: Date().timeIntervalSince1970, pid: pid)
if let out { print(out) }
exit(0)
