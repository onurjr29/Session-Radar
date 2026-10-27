import Foundation

public func endsWithQuestion(_ text: String) -> Bool {
    // ponytail: son satır sezgisi, URL'deki ? yanlış pozitif verebilir
    guard let last = text.split(whereSeparator: \.isNewline)
        .last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return false }
    return last.contains("?")
}

private func isValidSessionId(_ s: String) -> Bool {
    (1...64).contains(s.utf8.count) && s.utf8.allSatisfy {
        ($0 >= 48 && $0 <= 57) || ($0 >= 65 && $0 <= 90) || ($0 >= 97 && $0 <= 122) || $0 == 45
    }
}

public func makeHookEvent(from input: [String: Any], now: Double) -> HookEvent? {
    guard let name = input["hook_event_name"] as? String,
          let sid = input["session_id"] as? String, isValidSessionId(sid) else { return nil }
    var e = HookEvent(ts: now, event: name, sessionId: sid)
    e.cwd = input["cwd"] as? String
    e.transcriptPath = input["transcript_path"] as? String
    e.tool = input["tool_name"] as? String
    e.notificationType = input["notification_type"] as? String

    if let ti = input["tool_input"] as? [String: Any] {
        if let p = (ti["file_path"] ?? ti["notebook_path"]) as? String {
            e.target = p
        } else if let c = ti["command"] as? String {
            e.target = String(c.split(separator: "\n", omittingEmptySubsequences: false).first ?? "").prefix(120).description
        } else if let q = (ti["questions"] as? [[String: Any]])?.first?["question"] as? String {
            e.target = String(q.prefix(200))
        }
    }

    switch name {
    case "SessionStart": e.source = input["source"] as? String
    case "Notification": e.message = (input["message"] as? String).map { String($0.prefix(200)) }
    case "StopFailure": e.message = input["error"] as? String
    case "Stop":
        if let m = input["last_assistant_message"] as? String {
            e.message = String(m.suffix(300))
            e.endsWithQuestion = endsWithQuestion(m)
        }
        e.backgroundTasks = (input["background_tasks"] as? [Any])?.count
    default: break
    }
    return e
}

public func sessionStartContext(statusFile: URL) -> String {
    """
    Session Radar: Kullanıcı session'larını bir menü çubuğu uygulamasından takip ediyor. Kod değişikliği ya da çok adımlı bir iş yapıyorsan durumunu Write tool ile şu dosyaya yaz (her seferinde dosyanın tamamını yeniden yaz):
    \(statusFile.path)
    Biçim: {"task":"…","why":"…","phase":"…","next":"…","todo":[{"text":"…","done":false}],"problems":[]}
    Ne zaman: göreve başlarken, aşama değişince, iş bitince, bir sorun çıkınca veya çözülünce; her adımda değil. Alanlar Türkçe ve en fazla birer cümle olsun. Sorun çözülünce "problems" listesini boşalt. Basit soru-cevaplarda dosyayı yazma.
    """
}

public func appendLine(_ line: Data, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700])
    let fd = open(url.path, O_WRONLY | O_APPEND | O_CREAT, 0o600)
    guard fd >= 0 else { throw CocoaError(.fileWriteUnknown) }
    defer { close(fd) }
    var data = line
    data.append(0x0A)
    // tek write: eş zamanlı hook satırları birbirine karışmasın
    let n = data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
    guard n == data.count else { throw CocoaError(.fileWriteUnknown) }
}

public func runHook(stdin: Data, paths: RadarPaths, now: Double, pid: Int32? = nil) -> String? {
    guard let obj = try? JSONSerialization.jsonObject(with: stdin) as? [String: Any],
          var event = makeHookEvent(from: obj, now: now) else { return nil }
    event.pid = pid
    guard let line = try? JSONEncoder().encode(event) else { return nil }
    try? appendLine(line, to: paths.eventLog(event.sessionId))
    let state: TeamState? = readJSON(TeamState.self, from: paths.teamStateFile)
    let old = readJSON(TeamDelivered.self, from: paths.teamDelivered(event.sessionId)) ?? TeamDelivered()
    let r = teamHook(event, state: state, delivered: old, now: Date(timeIntervalSince1970: now))
    if r.delivered != old { try? writeJSON(r.delivered, to: paths.teamDelivered(event.sessionId)) }

    // yalnızca bağlam taşıyan olaylar notu tüketir (PreToolUse tüketmez)
    let closed = ["SessionStart", "UserPromptSubmit", "PostToolUse"].contains(event.event)
        ? closedNoteText(takeClosedNotes(paths.closedNotes(event.sessionId))) : nil
    let context = [r.context, closed].compactMap { $0 }.joined(separator: "\n\n")
    if event.event == "SessionStart" {
        let base = sessionStartContext(statusFile: paths.statusFile(event.sessionId))
        return context.isEmpty ? base : base + "\n\n" + context
    }
    var out: [String: Any]
    if let deny = r.deny {
        out = ["hookEventName": event.event, "permissionDecision": "deny", "permissionDecisionReason": deny]
    } else if !context.isEmpty {
        out = ["hookEventName": event.event, "additionalContext": context]
    } else { return nil }
    guard let data = try? JSONSerialization.data(withJSONObject: ["hookSpecificOutput": out]) else { return nil }
    return String(data: data, encoding: .utf8)
}
