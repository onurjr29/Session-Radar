import Foundation
import RadarCore

let out = runHook(stdin: FileHandle.standardInput.readDataToEndOfFile(),
                  paths: .fromEnvironment(), now: Date().timeIntervalSince1970)
if let out { print(out) }
exit(0)
