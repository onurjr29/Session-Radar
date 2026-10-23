# Session Radar MVP Uygulama Planı

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Onur'un makinesindeki tüm Claude Code session'larını canlı gösteren, bildirim gönderen ve session hakkında soru sorulabilen bir macOS menü çubuğu uygulaması.

**Architecture:** Claude Code hook'ları küçük bir `radar-hook` binary'sini çağırır. Bu binary her olayı `~/.session-radar/events/<session_id>.jsonl` dosyasına bir satır olarak ekler. Menü çubuğu uygulaması bu günlükleri, `claude agents --json` çıktısını, session durum dosyalarını, transcript'lerin son kısmını ve `git` çıktısını okuyup her session için bir anlık görüntü (`SessionSnapshot`) üretir. Tüm mantık, Foundation dışında bağımlılığı olmayan ve test edilebilen `RadarCore` kütüphanesinde durur. UI ince bir SwiftUI katmanıdır.

**Tech Stack:** Swift 6.4, SwiftPM, SwiftUI `MenuBarExtra`, Swift Testing, UserNotifications, ServiceManagement. Üçüncü taraf bağımlılık yok.

**Spec:** `docs/superpowers/specs/2026-10-23-session-radar-design.md`

## Global Constraints

- `swift-tools-version: 6.0`, `platforms: [.macOS(.v14)]`, Swift 6 dil modu. Üçüncü taraf paket eklenmez.
- `RadarCore` yalnızca `Foundation` import eder (AppKit, SwiftUI veya UserNotifications import etmez), çünkü `radar-hook` bu kütüphaneye bağlanıyor ve hızlı açılması gerekiyor.
- Veri kökü `~/.session-radar`. `SESSION_RADAR_HOME` ortam değişkeni tanımlıysa onun yerine o kullanılır (testler ve hook için).
- **Hook kuralları:** Hook her durumda exit 0 ile çıkar, ağa çıkmaz. `tool_input` alanından yalnızca dosya yolu, komutun ilk satırının ilk 120 karakteri ve AskUserQuestion sorusu alınır. `content`, `old_string` ve `new_string` asla yazılmaz.
- **"Soru sor" komutu birebir şu olacak:** `/usr/bin/env -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN <claude> -p --model haiku --tools "" --no-session-persistence --setting-sources project`. Çalışma klasörü `~/.session-radar/ask`, prompt stdin'den verilir. `--bare` asla kullanılmaz.
- cwd'si veri kökünün kendisi ya da altındaki bir klasör olan session'lar listelenmez.
- Bu aşamada Supabase'e veya ağa hiçbir şey yazılmaz.
- **Kullanıcı ayarları:** Kullanıcının `~/.claude/settings.json` dosyasındaki başka hiçbir anahtar ya da hook silinmez. Yazmadan önce yedek alınır. Dosya bozuksa hiçbir şey yazılmaz.
- UI metinleri Türkçe olur. Durum etiketleri şöyle: `working` "Çalışıyor", `waiting` "Seni bekliyor", `turnDone` "Tur bitti", `problem` "Sorun var", `closed` "Kapandı".
- Commit mesajları `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` satırıyla biter.
- Uygulama modülünün oluşturduğu public struct'lar açık bir `public init` içerir. Bunlar: `Activity`, `SessionInputs`, `RadarPaths`, ayrıca tüm alanları varsayılan `nil` olan `SessionStatus`. Testler `@testable import RadarCore` kullanır.

## Review Focus

1. **Finder'dan veya oturum açılışında başlatılan uygulamanın PATH'inde `~/.local/bin` yok.** Bu yüzden `claude` bulunamazsa liste boş kalır ve soru sorma çalışmaz. Beklenen davranış: aday yollarda ve login shell'de arayıp bulmak. Test: Task 7, `resolveClaudeFindsLocalBinWithBarePath`.
2. **`claude agents --json`, durdurulmuş arka plan session'larını da listeliyor** (`pid` alanı yok, `state: "blocked"`). Bunlar rozet sayısını şişirmemeli, "Kapandı" görünmeli. Test: Task 2, `resolveStoppedBackgroundIsClosed`. Task 5, `isAliveFalseWithoutPid`.
3. **Kullanıcının mevcut `settings.json` dosyası:** Başka hook'lar, izinler ve anahtarlar kurulumdan ve kaldırmadan sonra aynen kalmalı. Bozuk dosyaya hiçbir şey yazılmamalı. Test: Task 6, `mergePreservesUserContent`, `unmergeRestoresOriginal`, `installRefusesMalformedFile`.
4. **Dosya yollarında Türkçe karakter veya boşluk:** git bunları varsayılan olarak tırnaklayıp kaçış karakterleriyle yazıyor. Bu durumda çakışma sessizce kaçırılmamalı. Test: Task 4, `parsePorcelainHandlesRenameAndTurkish`, `repoInfoPendingIncludesDirtyAndUntracked`.
5. **Hook bir satırı yazarken uygulama aynı anda okursa yarım satır görür.** Olay kaybolmamalı ya da bozulmamalı. Test: Task 2, `readerWaitsForCompleteLine`.

---

## Dosya Yapısı

```
Package.swift
Sources/RadarCore/Models.swift        — tüm veri tipleri ve RadarPaths
Sources/RadarCore/HookRecord.swift    — hook girdisini HookEvent'e çevirme, satır ekleme, SessionStart metni
Sources/RadarCore/EventReducer.swift  — olaylardan Activity üretme, durum çözümleme, EventLogReader
Sources/RadarCore/Sources.swift       — agents JSON, durum dosyası, transcript okuma
Sources/RadarCore/Git.swift           — remote normalize, git çıktısı ayrıştırma, RepoInfo, çakışmalar
Sources/RadarCore/Snapshot.swift      — SessionSnapshot üretme, sıralama, rozet, bildirim geçişleri
Sources/RadarCore/Installer.swift     — settings.json birleştirme ve geri alma
Sources/RadarCore/Claude.swift        — claude yolunu bulma, agents yükleme, soru sorma
Sources/radar-hook/main.swift
Sources/SessionRadar/main.swift       — CLI (install/uninstall) veya uygulama
Sources/SessionRadar/RadarStore.swift — yenileme döngüsü, önbellekler, bildirimler
Sources/SessionRadar/PanelView.swift  — panel, satır, detay, soru alanı
Resources/Info.plist
scripts/build-app.sh
Tests/RadarCoreTests/*.swift
```

---

### Task 1: Paket, modeller ve hook kaydı (`radar-hook` uçtan uca)

**Files:**
- Create: `Package.swift`, `.gitignore` (`.build/`, `build/`), `Sources/RadarCore/Models.swift`, `Sources/RadarCore/HookRecord.swift`, `Sources/radar-hook/main.swift`
- Test: `Tests/RadarCoreTests/HookRecordTests.swift`

**Interfaces:**
- Produces (Models.swift; her tip `public`, `Sendable`, uygun yerde `Codable` ve `Equatable`):
  ```swift
  enum SessionState: String, Codable { case working, waiting, turnDone, problem, closed }
  struct HookEvent: Codable, Equatable { var ts: Double; var event: String; var sessionId: String
      var cwd: String?; var transcriptPath: String?; var tool: String?; var target: String?
      var notificationType: String?; var message: String?; var endsWithQuestion: Bool?; var backgroundTasks: Int? }
  struct TodoItem: Codable, Equatable { var text: String; var done: Bool }
  struct TopicItem: Codable, Equatable { var title: String; var state: String }   // "active" | "open" | "done"; bilinmeyen değer "open" gibi gösterilir
  struct SessionStatus: Codable, Equatable { var task, why, phase, next: String?; var todo: [TodoItem]?; var problems: [String]?; var topics: [TopicItem]? }
  struct AgentEntry: Codable, Equatable { var id: String?; var pid: Int32?; var sessionId: String; var name: String?
      var cwd: String; var kind: String; var startedAt: Double?; var status: String?; var state: String? }
  struct Progress: Equatable { var done: Int; var total: Int }
  struct SessionSnapshot: Identifiable, Equatable { var id: String; var name: String; var cwd: String
      var repoName: String?; var repoKey: String?; var branch: String?; var state: SessionState; var note: String?
      var task: String?; var action: String?; var progress: Progress?; var status: SessionStatus?
      var pendingFiles: Set<String>; var transcriptPath: String?; var updatedAt: Date }
  struct RadarPaths { let root: URL; init(root: URL)
      static func fromEnvironment(_ env: [String: String] = ProcessInfo.processInfo.environment) -> RadarPaths
      var eventsDir: URL; var statusDir: URL; var askDir: URL   // root/events, root/status, root/ask
      func eventLog(_ sessionId: String) -> URL                // events/<id>.jsonl
      func statusFile(_ sessionId: String) -> URL              // status/<id>.json
      func isInternal(cwd: String) -> Bool }                   // cwd == root veya root/ altı
  ```
- Produces (HookRecord.swift):
  ```swift
  public func makeHookEvent(from input: [String: Any], now: Double) -> HookEvent?
  public func endsWithQuestion(_ text: String) -> Bool
  public func sessionStartContext(statusFile: URL) -> String
  public func appendLine(_ line: Data, to url: URL) throws
  public func runHook(stdin: Data, paths: RadarPaths, now: Double) -> String?
  ```

- [ ] **Step 1: Write the failing tests** (`HookRecordTests.swift`, Swift Testing)

```swift
@Test func preToolUseWriteKeepsOnlyPath() throws {
    let e = try #require(makeHookEvent(from: ["hook_event_name": "PreToolUse", "session_id": "s-1",
        "tool_name": "Write", "tool_input": ["file_path": "/r/a.swift", "content": "SECRET"]], now: 1))
    #expect(e.target == "/r/a.swift")
    #expect(!String(decoding: try JSONEncoder().encode(e), as: UTF8.self).contains("SECRET"))
}
@Test func bashCommandIsFirstLineCappedAt120() throws {
    let cmd = String(repeating: "x", count: 300) + "\nsecond"
    let e = try #require(makeHookEvent(from: ["hook_event_name": "PreToolUse", "session_id": "s-1",
        "tool_name": "Bash", "tool_input": ["command": cmd]], now: 1))
    #expect(e.target == String(repeating: "x", count: 120))
}
@Test func stopCapturesQuestionAndBackgroundTasks() throws {
    let e = try #require(makeHookEvent(from: ["hook_event_name": "Stop", "session_id": "s-1",
        "last_assistant_message": "Tamam.\n\nOnaylıyor musun?", "background_tasks": [["id": "b1"]]], now: 1))
    #expect(e.endsWithQuestion == true && e.backgroundTasks == 1 && e.message == "Tamam.\n\nOnaylıyor musun?")
    #expect(endsWithQuestion("Bitti.") == false)
    #expect(endsWithQuestion("Soru?\n\nTamamlandı.") == false)
}
@Test func invalidSessionIdRejected() {
    #expect(makeHookEvent(from: ["hook_event_name": "Stop", "session_id": "../x"], now: 1) == nil)
}
@Test func runHookAppendsAndReturnsContextOnlyOnSessionStart() throws {
    let paths = RadarPaths(root: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
    let start = try JSONSerialization.data(withJSONObject: ["hook_event_name": "SessionStart", "session_id": "s-1", "cwd": "/r"])
    let ctx = try #require(runHook(stdin: start, paths: paths, now: 1))
    #expect(ctx.contains(paths.statusFile("s-1").path))
    let tool = try JSONSerialization.data(withJSONObject: ["hook_event_name": "PreToolUse", "session_id": "s-1", "tool_name": "Read"])
    #expect(runHook(stdin: tool, paths: paths, now: 2) == nil)
    let lines = try String(contentsOf: paths.eventLog("s-1"), encoding: .utf8).split(separator: "\n")
    #expect(lines.count == 2)
}
@Test func runHookIgnoresMalformedInput() {
    let paths = RadarPaths(root: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
    #expect(runHook(stdin: Data("not json".utf8), paths: paths, now: 1) == nil)
    #expect(!FileManager.default.fileExists(atPath: paths.eventsDir.path))
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter HookRecordTests`
Expected: Derleme hatası, `makeHookEvent` tanımlı değil.

- [ ] **Step 3: Write `Package.swift` and `Models.swift`**

`Package.swift` için hedefler: `RadarCore` (library), `radar-hook` (executable, RadarCore'a bağımlı) ve `RadarCoreTests`.

- [ ] **Step 4: Implement `HookRecord.swift` and `radar-hook/main.swift`**

- `session_id` şu kalıba uymuyorsa sonuç `nil` döner: `^[A-Za-z0-9-]{1,64}$`. Bu kural dosya yolu enjeksiyonunu engeller.
- **Alan eşlemesi:**
  - `hook_event_name` → `event`
  - `transcript_path` → `transcriptPath`
  - `tool_name` → `tool`
  - `target`: `tool_input.file_path` ya da `notebook_path`. Bunlar yoksa `command` alanının ilk satırının ilk 120 karakteri. AskUserQuestion için `questions[0].question` alanının ilk 200 karakteri.
  - `message`:
    - `Notification` olayında `message` alanının ilk 200 karakteri,
    - `StopFailure` olayında `error` alanı,
    - `Stop` olayında `last_assistant_message` alanının son 300 karakteri.
  - `Stop` olayında ayrıca: `endsWithQuestion` ve `backgroundTasks` (`background_tasks` dizisinin eleman sayısı).
- `endsWithQuestion` kuralı: Metnin son boş olmayan satırı `?` içeriyorsa `true` döner. Kodun yanına şu yorum eklenir: `// ponytail: son satır sezgisi, URL'deki ? yanlış pozitif verebilir`.
- `appendLine`: Önce klasörü oluşturur. Sonra dosyayı `open(path, O_WRONLY|O_APPEND|O_CREAT, 0o600)` ile açar ve satırı tek bir `write` çağrısıyla yazar. Satır `\n` ile biter. Eş zamanlı hook'lar birbirinin satırına karışmasın diye böyle yapılır.
- `runHook`: Bütün hataları yutar. Yalnızca `SessionStart` olayında `sessionStartContext(...)` döner.
- `sessionStartContext` metni birebir şu olacak (`<YOL>` yerine `statusFile.path` gelir):

```
Session Radar: Kullanıcı session'larını bir menü çubuğu uygulamasından takip ediyor. Kod değişikliği ya da çok adımlı bir iş yapıyorsan durumunu Write tool ile şu dosyaya yaz (her seferinde dosyanın tamamını yeniden yaz; dosya varsa önce Read ile oku ve "topics" listesini koruyarak güncelle):
<YOL>
Biçim: {"task":"…","why":"…","phase":"…","next":"…","todo":[{"text":"…","done":false}],"problems":[],"topics":[{"title":"…","state":"active"}]}
"topics": bu session'da baştan beri ele alınan konular, eskiden yeniye. Şu an çalışılan konu "active" (yalnızca bir tane), yarım kalıp dönülecek olanlar "open", kapananlar "done". Konu değişince eskisinin durumunu güncelle ve yenisini sona ekle.
Ne zaman: göreve başlarken, konu ya da aşama değişince, iş bitince, bir sorun çıkınca veya çözülünce; her adımda değil. Alanlar Türkçe ve en fazla birer cümle olsun. Sorun çözülünce "problems" listesini boşalt. Basit soru-cevaplarda dosyayı yazma.
```

- `radar-hook/main.swift`: stdin'in tamamını okur ve `runHook(stdin:paths: .fromEnvironment(), now: Date().timeIntervalSince1970)` çağırır. Dönen metin varsa `print` eder. Her durumda `exit(0)` ile çıkar.

- [ ] **Step 5: Run tests and an end-to-end check**

Run: `swift test --filter HookRecordTests` → Expected: tüm testler PASS.

Run: `swift build -c release && echo '{"hook_event_name":"SessionStart","session_id":"abc-1","cwd":"/tmp"}' | SESSION_RADAR_HOME=$PWD/.tmp-radar /usr/bin/time -p .build/release/radar-hook; cat .tmp-radar/events/abc-1.jsonl; rm -rf .tmp-radar`

Expected:
- İçinde `.tmp-radar/status/abc-1.json` geçen bağlam metni yazdırılır,
- günlükte tek bir JSON satırı vardır,
- `real` süresi 0,05 saniyenin altındadır.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: modeller ve radar-hook olay kaydı"
```

---

### Task 2: Olay indirgeme, durum çözümleme ve günlük okuyucu

**Files:**
- Create: `Sources/RadarCore/EventReducer.swift`
- Test: `Tests/RadarCoreTests/EventReducerTests.swift`

**Interfaces:**
- Consumes: Task 1'deki `HookEvent`, `SessionState`, `SessionStatus`, `AgentEntry`, `RadarPaths`.
- Produces:
  ```swift
  public struct Activity: Equatable, Sendable { public var state: SessionState = .turnDone; public var action: String?
      public var note: String?; public var touched: Set<String> = []; public var lastEventAt: Double?
      public var lastEvent: String?; public var ended = false; public var cwd: String?; public var transcriptPath: String? }
  public func apply(_ e: HookEvent, to a: inout Activity)
  public func reduceEvents(_ events: [HookEvent]) -> Activity          // Activity()'den başlayıp apply ile katlar
  public func describeAction(tool: String, target: String?) -> String
  public func resolveState(activity: Activity?, agent: AgentEntry?, alive: Bool, status: SessionStatus?) -> (state: SessionState, note: String?)
  public final class EventLogReader { public init(paths: RadarPaths); public func poll() -> [String: [HookEvent]]; public func forget(_ sessionId: String) }
  ```

**`apply` geçiş tablosu.** Her olay ayrıca `lastEventAt`, `lastEvent` alanlarını ve (nil değilse) `cwd` / `transcriptPath` alanlarını günceller. `target` değeri `/.session-radar/` içeren tool olayları tamamen yok sayılır.

| Olay | Etki |
|---|---|
| `SessionStart` | `state = .turnDone`, `action = nil`, `note = nil` |
| `UserPromptSubmit` | `state = .working`, `note = nil` |
| `PreToolUse`, tool `AskUserQuestion` | `state = .waiting`, `note = target` |
| `PreToolUse`, diğer tool'lar | `state = .working`, `note = nil`, `action = describeAction(...)` |
| `PostToolUse` | `waiting` durumundaysa `.working` olur ve `note = nil`. Tool `Edit`, `Write`, `MultiEdit` veya `NotebookEdit` ise ve `target` `/` ile başlıyorsa yol `touched` kümesine eklenir |
| `Notification` | `permission_prompt`, `elicitation_dialog`, `elicitation_url_dialog`, `agent_needs_input` → `.waiting`, `note = message`. `quota_auto_resume_stale`, `quota_auto_resume_disabled` → `.problem`, `note = message`. `quota_auto_resume_fired` → `.working`. `agent_completed` → `.turnDone`. Diğerleri yok sayılır |
| `Stop` | `backgroundTasks > 0` → `.working`, `action = "Arka plan işi bekleniyor"`. `endsWithQuestion == true` → `.waiting`, `note = message`, `action = nil`. Diğer durumlarda → `.turnDone`, `action = nil` |
| `StopFailure` | `.problem`, `note = "API hatası: " + message` |
| `SessionEnd` | `ended = true`, `state = .closed`, `action = nil` |

**`describeAction` biçimi:**
- `Edit`, `Write`, `MultiEdit`, `NotebookEdit` ve `Read` için hedefin dosya adı kullanılır: `"Edit · Home.tsx"`.
- `Bash` için hedef olduğu gibi yazılır: `"Bash · npm test"`.
- Diğer tool'larda yalnızca tool adı yazılır.

**`resolveState` kuralları (sırayla uygulanır):**
1. `activity?.ended` doğruysa → `.closed`.
2. `!alive` ise:
   - `activity` varsa ve durumu `.working` ya da `.waiting` ise → `(.problem, "Session beklenmedik şekilde kapandı")`.
   - Aksi halde → `.closed`.
3. `status.problems` içinde boş olmayan bir eleman varsa → `(.problem, problems.joined(separator: "; "))`.
4. `activity` varsa → `(activity.state, activity.note)`.
5. Ajan bilgisine düşülür:
   - `kind == "background"` ise: `state` `"working"` → `.working`, `"blocked"` → `.waiting`, diğer değerler → `.turnDone`.
   - Diğer session'larda: `status == "busy"` → `.working`, diğer değerler → `.turnDone`.

- [ ] **Step 1: Write the failing tests**

```swift
func ev(_ name: String, tool: String? = nil, target: String? = nil, nt: String? = nil, msg: String? = nil,
        q: Bool? = nil, bg: Int? = nil) -> HookEvent {
    HookEvent(ts: 1, event: name, sessionId: "s", cwd: nil, transcriptPath: nil, tool: tool, target: target,
              notificationType: nt, message: msg, endsWithQuestion: q, backgroundTasks: bg)
}
@Test func reduceFollowsTurnLifecycle() {
    var a = reduceEvents([ev("SessionStart"), ev("UserPromptSubmit"), ev("PreToolUse", tool: "Edit", target: "/r/a.swift")])
    #expect(a.state == .working && a.action == "Edit · a.swift")
    apply(ev("PostToolUse", tool: "Edit", target: "/r/a.swift"), to: &a);  #expect(a.touched == ["/r/a.swift"])
    apply(ev("Stop", msg: "Devam edeyim mi?", q: true), to: &a);          #expect(a.state == .waiting && a.note == "Devam edeyim mi?")
    apply(ev("UserPromptSubmit"), to: &a);                                #expect(a.state == .working && a.note == nil)
    apply(ev("Notification", nt: "permission_prompt", msg: "izin"), to: &a); #expect(a.state == .waiting)
    apply(ev("PostToolUse", tool: "Bash", target: "ls"), to: &a);         #expect(a.state == .working)
    apply(ev("Stop", bg: 1), to: &a);                                     #expect(a.state == .working)
    apply(ev("Stop", q: false), to: &a);                                  #expect(a.state == .turnDone && a.action == nil)
    apply(ev("StopFailure", msg: "rate_limit"), to: &a);                  #expect(a.state == .problem && a.note == "API hatası: rate_limit")
    apply(ev("SessionEnd"), to: &a);                                      #expect(a.ended && a.state == .closed)
}
@Test func radarOwnFilesAreIgnored() {
    let a = reduceEvents([ev("Stop", q: false), ev("PreToolUse", tool: "Write", target: "/Users/o/.session-radar/status/s.json")])
    #expect(a.state == .turnDone && a.action == nil)
}
@Test func resolveRules() {
    var working = Activity(); working.state = .working
    var ended = Activity(); ended.ended = true
    #expect(resolveState(activity: ended, agent: nil, alive: true, status: nil).state == .closed)
    #expect(resolveState(activity: working, agent: nil, alive: false, status: nil) == (.problem, "Session beklenmedik şekilde kapandı"))
    #expect(resolveState(activity: Activity(), agent: nil, alive: false, status: nil).state == .closed)
    #expect(resolveState(activity: working, agent: nil, alive: true, status: SessionStatus(problems: ["build kırık"])) == (.problem, "build kırık"))
}
@Test func resolveFallsBackToAgentWithoutEvents() {
    let bg = AgentEntry(id: "x", pid: 1, sessionId: "s", name: nil, cwd: "/r", kind: "background", startedAt: nil, status: nil, state: "blocked")
    let it = AgentEntry(id: nil, pid: 2, sessionId: "s", name: nil, cwd: "/r", kind: "interactive", startedAt: nil, status: "busy", state: nil)
    #expect(resolveState(activity: nil, agent: bg, alive: true, status: nil).state == .waiting)
    #expect(resolveState(activity: nil, agent: it, alive: true, status: nil).state == .working)
}
@Test func resolveStoppedBackgroundIsClosed() {
    let stopped = AgentEntry(id: "x", pid: nil, sessionId: "s", name: nil, cwd: "/r", kind: "background", startedAt: nil, status: nil, state: "blocked")
    #expect(resolveState(activity: nil, agent: stopped, alive: false, status: nil).state == .closed)
}
@Test func readerWaitsForCompleteLine() throws {
    let paths = RadarPaths(root: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
    let line = String(decoding: try JSONEncoder().encode(ev("Stop")), as: UTF8.self)
    try appendLine(Data((line + "\n").utf8), to: paths.eventLog("s"))
    let h = try FileHandle(forWritingTo: paths.eventLog("s")); try h.seekToEnd()
    try h.write(contentsOf: Data(line.prefix(10).utf8))
    let r = EventLogReader(paths: paths)
    #expect(r.poll()["s"]?.count == 1)
    try h.write(contentsOf: Data((line.dropFirst(10) + "\nnot json\n").utf8)); try h.close()
    #expect(r.poll()["s"]?.count == 1)
    #expect(r.poll().isEmpty)
}
```

`SessionStatus(problems:)` ve buna benzer kısmi başlatıcılar için `SessionStatus` tipine tüm alanları varsayılan `nil` olan bir `public init` eklenir (Task 1 dosyasında).

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter EventReducerTests` → Expected: derleme hatası (`reduceEvents` tanımlı değil).

- [ ] **Step 3: Implement `EventReducer.swift`**

`EventLogReader.poll()`:
- `eventsDir` içindeki ve son 7 gün içinde değiştirilmiş `*.jsonl` dosyalarını tarar.
- Her dosya için bir byte offset tutar ve offset'ten sonra yalnızca son `\n` karakterine kadar olan kısmı tüketir.
- Bozuk satırları atlar.
- Dosya adından gelen `sessionId` değerini anahtar olarak kullanır.

- [ ] **Step 4: Run tests** — `swift test --filter EventReducerTests` → Expected: PASS.

- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: olay indirgeme ve durum çözümleme"`

---

### Task 3: Veri kaynakları (agents, durum dosyası, transcript)

**Files:**
- Create: `Sources/RadarCore/Sources.swift`
- Test: `Tests/RadarCoreTests/SourcesTests.swift`

**Interfaces:**
- Consumes: Task 1'deki `AgentEntry` ve `SessionStatus`, Task 2'deki `describeAction`.
- Produces:
  ```swift
  public func parseAgents(_ data: Data) -> [AgentEntry]                    // bozuk girdi → []
  public func loadStatus(_ url: URL) -> SessionStatus?                     // yoksa, bozuksa ya da 64 KB'tan büyükse → nil
  public struct TranscriptInfo: Equatable, Sendable { public var aiTitle: String?; public var lastPrompt: String?
      public var lastAction: String?; public var dialogue: [String] }
  public func readTranscriptTail(_ url: URL, maxBytes: Int = 512_000) -> TranscriptInfo
  public func findTranscript(sessionId: String, projectsDir: URL) -> URL?  // projectsDir/*/<id>.jsonl
  ```

**Transcript kuralları:**
- Dosyanın son `maxBytes` kadarı okunur. Okumaya dosyanın ortasından başlandıysa ilk satır yarım olduğu için atılır.
- `aiTitle`: kuyruktaki son `ai-title` satırından alınır.
- `lastPrompt`: son `last-prompt` satırının `lastPrompt` alanından alınır. Böyle bir satır yoksa, `content` alanı string olan son `user` satırı kullanılır.
- `lastAction`: son asistan mesajındaki son `tool_use` bloğundan, `describeAction(tool: name, target: input.file_path ?? input.command)` ile üretilir.
- `dialogue`: kronolojik sırayla üretilir.
  - `"Kullanıcı: …"` girdileri: `isMeta` alanı `true` olmayan ve `content` alanı string olan `user` satırlarından gelir. `content` alanı dizi olanlar tool sonucudur ve atlanır.
  - `"Claude: …"` girdileri: asistan mesajlarındaki `text` bloklarının birleşiminden gelir.
  - Her girdi en fazla 2000 karakter olur.

- [ ] **Step 1: Write the failing tests** (fixture test içinde geçici dosyaya yazılır)

```swift
let fixture = """
{"type":"ai-title","aiTitle":"Giriş ekranı hatası","sessionId":"s1"}
{"type":"user","isMeta":false,"message":{"role":"user","content":"Login butonu çalışmıyor, düzelt"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Bakıyorum."},{"type":"tool_use","id":"t1","name":"Edit","input":{"file_path":"/r/Login.tsx","old_string":"a","new_string":"b"}}]}}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"ok"}]}}
{"type":"last-prompt","lastPrompt":"Login butonu çalışmıyor, düzelt","sessionId":"s1"}
"""
@Test func transcriptTailExtractsInfo() throws {
    let url = try tempFile(fixture)
    let t = readTranscriptTail(url)
    #expect(t.aiTitle == "Giriş ekranı hatası" && t.lastPrompt == "Login butonu çalışmıyor, düzelt")
    #expect(t.lastAction == "Edit · Login.tsx")
    #expect(t.dialogue == ["Kullanıcı: Login butonu çalışmıyor, düzelt", "Claude: Bakıyorum."])
}
@Test func transcriptTailSurvivesCutLine() throws {
    let t = readTranscriptTail(try tempFile(fixture), maxBytes: 120)
    #expect(t.lastPrompt == "Login butonu çalışmıyor, düzelt")
}
@Test func agentsParsing() {
    let json = #"[{"id":"eb81","cwd":"/r","kind":"background","startedAt":1,"sessionId":"a","name":"n","state":"blocked"},{"pid":23183,"cwd":"/r","kind":"interactive","startedAt":2,"sessionId":"b","name":"mobile-worker","status":"idle"}]"#
    let a = parseAgents(Data(json.utf8))
    #expect(a.count == 2 && a[0].pid == nil && a[1].pid == 23183 && a[1].status == "idle")
    #expect(parseAgents(Data("garbage".utf8)).isEmpty)
}
@Test func statusLoadingIsTolerant() throws {
    let s = loadStatus(try tempFile(#"{"task":"Login düzelt","todo":[{"text":"a","done":true}],"topics":[{"title":"Giriş","state":"done"},{"title":"Login","state":"active"}],"extra":1}"#))
    #expect(s?.task == "Login düzelt" && s?.todo?.first?.done == true && s?.why == nil)
    #expect(s?.topics?.map(\.state) == ["done", "active"])
    #expect(loadStatus(try tempFile("{bozuk")) == nil)
}
```

`tempFile(_:) -> URL` küçük bir yardımcı fonksiyondur. İçeriği UUID adlı geçici bir dosyaya yazar ve dosyanın URL'ini döner. Bu dosyada tanımlanır.

- [ ] **Step 2: Run** — `swift test --filter SourcesTests` → Expected: derleme hatası.
- [ ] **Step 3: Implement `Sources.swift`.**
- [ ] **Step 4: Run** — `swift test --filter SourcesTests` → Expected: PASS.
- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: agents, durum dosyası ve transcript okuma"`

---

### Task 4: Git bilgisi ve çakışma tespiti

**Files:**
- Create: `Sources/RadarCore/Git.swift`
- Test: `Tests/RadarCoreTests/GitTests.swift`

**Interfaces:**
- Consumes: Task 1'deki `SessionSnapshot` (`id`, `repoKey`, `pendingFiles`).
- Produces:
  ```swift
  public func normalizeRemote(_ url: String) -> String
  public func parseNulPaths(_ data: Data, porcelain: Bool) -> Set<String>
  public struct RepoInfo: Equatable, Sendable { public var toplevel: String; public var key: String
      public var name: String; public var branch: String?; public var pending: Set<String> }
  public func repoInfo(cwd: String, git: String = "/usr/bin/git") -> RepoInfo?
  public func pendingTouched(_ touched: Set<String>, repo: RepoInfo) -> Set<String>
  public struct Conflict: Hashable, Sendable { public var a: String; public var b: String; public var files: [String]
      public var pairKey: String { "\(a)|\(b)" } }                      // a < b, files sıralı
  public func findConflicts(_ sessions: [SessionSnapshot]) -> [Conflict]
  ```

**Kurallar:**
- **`normalizeRemote`:**
  - şemayı, `user:parola@` kısmını ve portu atar,
  - `git@host:org/repo` biçimini `host/org/repo` biçimine çevirir,
  - sondaki `.git` ve `/` karakterlerini atar,
  - sonucu küçük harfe çevirir.
  - Kimlik bilgisi asla saklanmaz.
- **`repoInfo`:** Komutların hepsi `git -C <cwd>` ile çalışır.
  - `toplevel`: `rev-parse --show-toplevel`. Bu komut başarısız olursa fonksiyon `nil` döner.
  - `key`: `remote get-url origin` çıktısı normalize edilerek. Remote yoksa `"local:" + toplevel`.
  - `name`: `key` değerinin son yol bileşeni.
  - `branch`: `branch --show-current`. Çıktı boşsa `nil`.
  - `pending` iki listenin birleşimidir:
    - `-c core.quotePath=false status --porcelain -z`,
    - `diff --name-only -z @{upstream}...HEAD`. Bu başarısız olursa `origin/HEAD...HEAD` denenir, o da başarısız olursa bu kısım boş kalır.
- **`parseNulPaths(porcelain: true)`:** Her kayıt `XY yol` biçimindedir. `X` değeri `R` ya da `C` ise, ardından gelen NUL ile ayrılmış alan eski yoldur ve atlanır.
- **`pendingTouched`:** Hem dokunulan yollar hem `toplevel` değeri `resolvingSymlinksInPath()` ile çözülür (`/var` → `/private/var`). Sonra yollar köke göre göreli hâle getirilir ve `pending` ile kesişimleri alınır.
- **`findConflicts`:** Aynı `repoKey` değerine sahip ve `pendingFiles` kümeleri kesişen her session çifti için bir `Conflict` üretilir. `repoKey` değeri `nil` olan session'lar yok sayılır.

- [ ] **Step 1: Write the failing tests**

```swift
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
    let dir = try tempGitRepo()                        // git init -b main, a.txt commit'li
    try "x".write(to: dir.appending(path: "a.txt"), atomically: true, encoding: .utf8)
    try "y".write(to: dir.appending(path: "çalışma.txt"), atomically: true, encoding: .utf8)
    let info = try #require(repoInfo(cwd: dir.path))
    #expect(info.pending == ["a.txt", "çalışma.txt"] && info.branch == "main" && info.key.hasPrefix("local:"))
    #expect(pendingTouched([dir.path + "/a.txt", "/baska/yer.txt"], repo: info) == ["a.txt"])
}
@Test func repoInfoPendingIncludesUnpushedNotPushed() throws {
    let (clone, bare) = try tempClonedRepo()           // bare origin + clone; b.txt push'lanmış, c.txt commit'li ama push'lanmamış
    let info = try #require(repoInfo(cwd: clone.path))
    #expect(info.pending.contains("c.txt") && !info.pending.contains("b.txt"))
    #expect(info.key == normalizeRemote(bare.path))
}
@Test func conflictsOnlyWithinSameRepo() {
    func s(_ id: String, _ key: String?, _ f: Set<String>) -> SessionSnapshot { /* yalnızca id, repoKey, pendingFiles dolu */ }
    let c = findConflicts([s("S1", "k", ["a", "b"]), s("S2", "k", ["b", "c"]), s("S3", "k2", ["b"]), s("S4", nil, ["b"])])
    #expect(c == [Conflict(a: "S1", b: "S2", files: ["b"])])
}
```

`tempGitRepo()` ve `tempClonedRepo()` yardımcıları `/usr/bin/git` komutunu `Process` ile çalıştırır ve depoyu `user.email` / `user.name` ayarlarıyla kurar. Bu test dosyasında tanımlanırlar.

- [ ] **Step 2: Run** — `swift test --filter GitTests` → Expected: derleme hatası.
- [ ] **Step 3: Implement `Git.swift`.** `Process` çalıştırmak için tek bir dahili yardımcı yazılır, `run(_ args: [String], cwd: String) -> Data?`. Komut sıfır dışı bir kodla çıkarsa `nil` döner.
- [ ] **Step 4: Run** — `swift test --filter GitTests` → Expected: PASS.
- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: git bilgisi ve çakışma tespiti"`

---

### Task 5: Anlık görüntü üretimi ve bildirim geçişleri

**Files:**
- Create: `Sources/RadarCore/Snapshot.swift`
- Test: `Tests/RadarCoreTests/SnapshotTests.swift`

**Interfaces:**
- Consumes: Task 2'deki `Activity` ve `resolveState`, Task 3'teki `TranscriptInfo`, Task 4'teki `RepoInfo`, `pendingTouched` ve `Conflict`.
- Produces:
  ```swift
  public struct SessionInputs: Sendable { public var sessionId: String; public var agent: AgentEntry?; public var alive: Bool
      public var activity: Activity?; public var status: SessionStatus?; public var transcript: TranscriptInfo?
      public var repo: RepoInfo?; public var lastSeen: Date }
  public func isAlive(_ agent: AgentEntry?, probe: (Int32) -> Bool = { kill($0, 0) == 0 }) -> Bool
  public func buildSnapshot(_ i: SessionInputs) -> SessionSnapshot
  public func shouldKeep(_ s: SessionSnapshot, alive: Bool, now: Date) -> Bool     // alive || now - updatedAt < 24 saat
      // ponytail: 24 saatten eski kapanmış session'ların push'lanmamış dosyaları çakışma kontrolüne girmez; gerekirse kişi bazlı kalıcı kayıt
  public func topicSummary(_ topics: [TopicItem]?) -> (current: String?, open: Int)  // current: son "active" başlık; open: "open" sayısı
  public func sortForDisplay(_ s: [SessionSnapshot]) -> [SessionSnapshot]          // waiting, problem, working, turnDone, closed; sonra updatedAt azalan
  public func badgeCount(_ s: [SessionSnapshot]) -> Int                            // waiting + problem
  public struct RadarNotification: Equatable, Sendable { public var id: String; public var title: String; public var body: String }
  public func transitions(previous: [String: SessionState]?, previousConflictPairs: Set<String>,
                          current: [SessionSnapshot], conflicts: [Conflict]) -> [RadarNotification]
  ```

**`buildSnapshot` kuralları:**

| Alan | Kaynak |
|---|---|
| `name` | `agent.name ?? transcript.aiTitle ?? cwd'nin son bileşeni` |
| `cwd` | `agent.cwd ?? activity.cwd ?? ""` |
| `state`, `note` | `resolveState(...)` |
| `task` | `status.task ?? lastPrompt` (`lastPrompt` ilk satırı, en fazla 80 karakter; kesilirse sonuna `…` eklenir) |
| `action` | Yalnızca `state == .working` iken: `activity.action ?? transcript.lastAction` |
| `progress` | `todo` boş değilse `Progress(done: tamamlananlar, total: hepsi)` |
| `repoName`, `repoKey`, `branch` | `repo` değerinden |
| `pendingFiles` | `pendingTouched(activity.touched, repo)`. `repo` yoksa `[]` |
| `updatedAt` | `activity.lastEventAt ?? agent.startedAt / 1000 ?? lastSeen`. `startedAt` milisaniye cinsinden |

**`transitions` kuralları:**
- `previous == nil` ise uygulama yeni açılmıştır. Hiç bildirim üretilmez, yalnızca başlangıç durumu kaydedilir.
- Önceki durumu olmayan session, önceki durumu "yok" kabul edilerek değerlendirilir.

| Geçiş | Başlık | Gövde |
|---|---|---|
| önceki ≠ `waiting`, şimdiki = `waiting` | `"\(name) seni bekliyor"` | `note ?? task ?? ""` |
| önceki = `working`, şimdiki = `turnDone` | `"\(name) işini bitirdi"` | `task ?? ""` |
| önceki ≠ `problem`, şimdiki = `problem` | `"\(name): sorun var"` | `note ?? ""` |
| `pairKey` değeri `previousConflictPairs` içinde olmayan çakışma | `"Çakışma: \(adA) ↔ \(adB)"` | İlk 3 dosya `", "` ile birleştirilir, daha fazlası varsa `" +N"` eklenir |

`id` değeri `"\(sessionId):\(state.rawValue)"` olur. Çakışmalarda `"conflict:\(pairKey)"` olur.

- [ ] **Step 1: Write the failing tests**

```swift
func snap(_ id: String, _ st: SessionState, note: String? = nil, task: String? = nil) -> SessionSnapshot { /* name = id */ }
@Test func seedProducesNothing() {
    #expect(transitions(previous: nil, previousConflictPairs: [], current: [snap("A", .waiting)], conflicts: []).isEmpty)
}
@Test func notifiesOnMeaningfulTransitions() {
    let n = transitions(previous: ["A": .working, "B": .turnDone, "C": .waiting, "D": .working],
                        previousConflictPairs: [],
                        current: [snap("A", .turnDone, task: "Login"), snap("B", .waiting, note: "Onay?"),
                                  snap("C", .waiting), snap("D", .problem, note: "build kırık"), snap("E", .waiting)],
                        conflicts: [])
    #expect(n.map(\.title) == ["A işini bitirdi", "B seni bekliyor", "D: sorun var", "E seni bekliyor"])
    #expect(n[1].body == "Onay?")
}
@Test func conflictNotifiedOncePerPair() {
    let c = Conflict(a: "A", b: "B", files: ["x", "y", "z", "w"])
    let first = transitions(previous: [:], previousConflictPairs: [], current: [snap("A", .working), snap("B", .working)], conflicts: [c])
    #expect(first.map(\.body) == ["x, y, z +1"])
    #expect(transitions(previous: [:], previousConflictPairs: [c.pairKey], current: [], conflicts: [c]).isEmpty)
}
@Test func isAliveFalseWithoutPid() {
    let a = AgentEntry(id: "x", pid: nil, sessionId: "s", name: nil, cwd: "/r", kind: "background", startedAt: nil, status: nil, state: "blocked")
    #expect(!isAlive(a, probe: { _ in true }) && !isAlive(nil))
}
@Test func snapshotFallsBackToTranscript() {
    let s = buildSnapshot(SessionInputs(sessionId: "s", agent: nil, alive: true, activity: nil, status: nil,
        transcript: TranscriptInfo(aiTitle: "Başlık", lastPrompt: String(repeating: "a", count: 100) + "\nikinci", lastAction: "Edit · x.swift", dialogue: []),
        repo: nil, lastSeen: Date(timeIntervalSince1970: 5)))
    #expect(s.name == "Başlık" && s.task == String(repeating: "a", count: 80) + "…" && s.updatedAt.timeIntervalSince1970 == 5)
}
@Test func topicSummaryCountsOpen() {
    let t = [TopicItem(title: "A", state: "done"), TopicItem(title: "B", state: "open"), TopicItem(title: "C", state: "active")]
    let s = topicSummary(t)
    #expect(s.current == "C" && s.open == 1)
    #expect(topicSummary(nil).current == nil && topicSummary(nil).open == 0)
}
@Test func badgeAndOrder() {
    let list = [snap("w", .working), snap("c", .closed), snap("q", .waiting), snap("p", .problem)]
    #expect(badgeCount(list) == 2 && sortForDisplay(list).map(\.id) == ["q", "p", "w", "c"])
}
```

Sıralama, `current` dizisinin sırasını korur. Çakışma bildirimleri en sona eklenir.

- [ ] **Step 2: Run** — `swift test --filter SnapshotTests` → Expected: derleme hatası.
- [ ] **Step 3: Implement `Snapshot.swift`.**
- [ ] **Step 4: Run** — `swift test --filter SnapshotTests` → Expected: PASS.
- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: anlık görüntü ve bildirim geçişleri"`

---

### Task 6: settings.json kurulumu ve kaldırılması

**Files:**
- Create: `Sources/RadarCore/Installer.swift`
- Test: `Tests/RadarCoreTests/InstallerTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public let radarHookEvents = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Notification", "Stop", "StopFailure", "SessionEnd"]
  public let radarPermissionRules = ["Edit(~/.session-radar/status/**)", "Read(~/.session-radar/status/**)"]
  public func mergeSettings(_ s: [String: Any], hookCommand: String) -> [String: Any]
  public func unmergeSettings(_ s: [String: Any]) -> [String: Any]
  public enum InstallError: Error { case unreadableSettings(String) }
  public func installSettings(at url: URL, hookCommand: String) throws
  public func uninstallSettings(at url: URL) throws
  ```

**Kurallar:**
- **Bize ait hook'u tanımak:** `command` alanında `radar-hook` geçen hook nesneleri bizimdir.
- **`mergeSettings`:**
  1. Önce `unmergeSettings` uygulanır, böylece işlem tekrar çalıştırılabilir olur.
  2. Ardından `radarHookEvents` listesindeki her olaya matcher içermeyen şu grup eklenir: `{"hooks":[{"type":"command","command":hookCommand,"timeout":5}]}`.
  3. `permissions.allow` listesine `radarPermissionRules` içindeki kurallar, listede yoksa eklenir.
- **`unmergeSettings`:**
  - Bize ait hook nesneleri silinir.
  - Bu yüzden boşalan gruplar, olay dizileri ve `hooks` anahtarı da silinir.
  - Bizim izin kurallarımız silinir.
- **`installSettings`:**
  - Dosya yoksa boş ayarlarla (`{}`) başlanır.
  - Dosya okunamıyor ya da JSON nesnesi değilse `InstallError` fırlatılır ve hiçbir şey yazılmaz.
  - Yazmadan önce `<ad>.session-radar.bak` yedeği alınır.
  - Dosya `[.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]` seçenekleriyle atomik olarak yazılır.

- [ ] **Step 1: Write the failing tests**

```swift
let user: [String: Any] = ["theme": "dark",
    "permissions": ["allow": ["Bash(ls:*)"], "defaultMode": "auto"],
    "hooks": ["PreToolUse": [["matcher": "Bash", "hooks": [["type": "command", "command": "~/x.sh"]]]]]]
func canon(_ d: [String: Any]) -> String { String(decoding: try! JSONSerialization.data(withJSONObject: d, options: .sortedKeys), as: UTF8.self) }
@Test func mergePreservesUserContent() throws {
    let m = mergeSettings(user, hookCommand: "\"/A/radar-hook\"")
    let hooks = try #require(m["hooks"] as? [String: [[String: Any]]])
    #expect(m["theme"] as? String == "dark" && Set(hooks.keys) == Set(radarHookEvents))
    #expect(hooks["PreToolUse"]?.count == 2)
    #expect((m["permissions"] as? [String: Any])?["allow"] as? [String] == ["Bash(ls:*)"] + radarPermissionRules)
}
@Test func mergeIsIdempotent() {
    let once = mergeSettings(user, hookCommand: "\"/A/radar-hook\"")
    #expect(canon(mergeSettings(once, hookCommand: "\"/A/radar-hook\"")) == canon(once))
}
@Test func unmergeRestoresOriginal() {
    #expect(canon(unmergeSettings(mergeSettings(user, hookCommand: "\"/A/radar-hook\""))) == canon(user))
}
@Test func installRefusesMalformedFile() throws {
    let url = try tempFile("{ bozuk")
    #expect(throws: InstallError.self) { try installSettings(at: url, hookCommand: "x/radar-hook") }
    #expect(try String(contentsOf: url, encoding: .utf8) == "{ bozuk")
    #expect(!FileManager.default.fileExists(atPath: url.path + ".session-radar.bak"))
}
@Test func installCreatesMissingFile() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".json")
    try installSettings(at: url, hookCommand: "x/radar-hook")
    let d = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    #expect((d?["hooks"] as? [String: Any])?.count == radarHookEvents.count)
}
```

`tempFile` yardımcısı Task 3'te tanımlandı. Testler aynı test hedefinde olduğu için doğrudan kullanılabilir.

- [ ] **Step 2: Run** — `swift test --filter InstallerTests` → Expected: derleme hatası.
- [ ] **Step 3: Implement `Installer.swift`.**
- [ ] **Step 4: Run** — `swift test --filter InstallerTests` → Expected: PASS.
- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: settings.json kurulum ve kaldırma"`

---

### Task 7: Claude ile konuşma (yol bulma, agents, soru sorma)

**Files:**
- Create: `Sources/RadarCore/Claude.swift`
- Test: `Tests/RadarCoreTests/ClaudeTests.swift`

**Interfaces:**
- Consumes: Task 1'deki `RadarPaths` ve `SessionStatus`, Task 3'teki `parseAgents`.
- Produces:
  ```swift
  public func resolveClaudePath(home: String, env: [String: String],
                                isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
                                shellLookup: () -> String? = loginShellLookup) -> String?
  public func loginShellLookup() -> String?                 // /bin/zsh -lc 'command -v claude'
  public func loadAgents(claudePath: String) -> [AgentEntry] // "<claude> agents --json", 15 sn zaman aşımı
  public func buildAskPrompt(question: String, status: SessionStatus?, dialogue: [String], maxDialogueChars: Int = 20_000) -> String
  public enum AskError: Error, Equatable { case failed(String), timedOut }
  public func runAsk(prompt: String, claudePath: String, paths: RadarPaths, timeout: TimeInterval = 120) async throws -> String
  ```

**Kurallar:**
- **`resolveClaudePath`:** Adaylar şu sırayla denenir ve çalıştırılabilir olan ilk aday seçilir:
  1. `env["PATH"]` içindeki her klasördeki `claude`,
  2. `"\(home)/.local/bin/claude"`,
  3. `/opt/homebrew/bin/claude`,
  4. `/usr/local/bin/claude`.

  Hiçbiri yoksa `shellLookup()` çağrılır.
- **`runAsk`:** Global Constraints'teki komutu birebir çalıştırır.
  - `executableURL = /usr/bin/env`, `currentDirectoryURL = paths.askDir` (klasör yoksa oluşturulur).
  - Prompt stdin'e yazılır ve stdin kapatılır.
  - Komut sıfırdan farklı bir kodla çıkarsa `AskError.failed(stderr)` fırlatılır.
  - Süre aşılırsa süreç sonlandırılır ve `AskError.timedOut` fırlatılır.
  - Başarılı olursa stdout, baştaki ve sondaki boşluklar kırpılmış olarak döner.
- **`buildAskPrompt` metni:**

```
Aşağıda bir Claude Code session'ı hakkında bilgiler var. Kullanıcının sorusunu yalnızca bu bilgilere dayanarak Türkçe ve kısa (en fazla 5 cümle) cevapla. Bilgi yoksa bilmediğini söyle.

## Durum dosyası
<status JSON'u ya da "yok">

## Son konuşma (eskiden yeniye)
<dialogue satırları, \n ile; toplam maxDialogueChars'ı aşarsa en eski satırlar atılır>

## Soru
<question>
```

- [ ] **Step 1: Write the failing tests**

```swift
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
    #expect(out.contains("pwd:" + paths.askDir.resolvingSymlinksInPath().path))
}
@Test func runAskSurfacesFailure() async throws {
    let fake = try executableScript("#!/bin/sh\necho boom >&2\nexit 2\n")
    let paths = RadarPaths(root: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
    await #expect(throws: AskError.failed("boom")) { try await runAsk(prompt: "x", claudePath: fake.path, paths: paths) }
}
```

`executableScript(_:) -> URL` yardımcısı içeriği geçici bir dosyaya yazar, dosyaya `chmod 755` uygular ve URL'ini döner. Bu test dosyasında tanımlanır.

- [ ] **Step 2: Run** — `swift test --filter ClaudeTests` → Expected: derleme hatası.
- [ ] **Step 3: Implement `Claude.swift`.**
- [ ] **Step 4: Run** — `swift test --filter ClaudeTests` → Expected: PASS.
- [ ] **Step 5: Haiku takma adını gerçek makinede doğrula** (abonelik kotasından küçük bir harcama)

Run: `cd "$(mktemp -d)" && echo "Sadece 'tamam' yaz." | /usr/bin/env -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN ~/.local/bin/claude -p --model haiku --tools "" --no-session-persistence --setting-sources project`

Expected: Kısa bir cevap gelir (ör. "tamam"). Hata gelirse durulur ve kullanıcıya bildirilir.

- [ ] **Step 6: Commit** — `git add -A && git commit -m "feat: claude yolu, agents ve soru sorma"`

---

### Task 8: Menü çubuğu uygulaması, paketleme ve kurulum

**Files:**
- Modify: `Package.swift` (`SessionRadar` executable hedefi eklenir, RadarCore'a bağımlı)
- Create: `Sources/SessionRadar/main.swift`, `Sources/SessionRadar/RadarStore.swift`, `Sources/SessionRadar/PanelView.swift`, `Resources/Info.plist`, `scripts/build-app.sh`, `README.md`

**Interfaces:**
- Consumes: Task 1–7'deki tüm public API.
- Produces:
  ```swift
  @MainActor @Observable final class RadarStore {
      var sessions: [SessionSnapshot]; var conflicts: [Conflict]; var lastError: String?
      func start(); func ask(_ question: String, about sessionId: String) async -> String }
  ```

**`main.swift`:**
- Argüman `install` ise:
  - Hook komutu, `Bundle.main.executableURL` değerinin bulunduğu klasördeki `radar-hook` binary'si olur, tırnak içinde verilir.
  - `installSettings(at: ~/.claude/settings.json, hookCommand:)` çağrılır.
  - `events`, `status` ve `ask` klasörleri oluşturulur.
  - Değişiklik özeti yazdırılır ve program çıkar.
- Argüman `uninstall` ise `uninstallSettings` çağrılır ve program çıkar.
- Diğer durumlarda `SessionRadarApp.main()` çalışır. `SessionRadarApp` bu dosyada tanımlanır.

**`SessionRadarApp`:**
- `MenuBarExtra` ile `.menuBarExtraStyle(.window)` kullanılır.
- Etiket `Image(systemName: "dot.radiowaves.left.and.right")` olur. `badgeCount > 0` ise yanında sayı gösterilir.
- İlk açılışta:
  - `UNUserNotificationCenter.requestAuthorization([.alert, .sound])` istenir,
  - `SMAppService.mainApp.register()` çağrılır. Hata olursa yalnızca `lastError` alanına yazılır.

**`RadarStore` döngüsü:**
- **Her saniye:**
  - `EventLogReader.poll()` ile yeni olaylar alınıp `apply` ile işlenir,
  - durum dosyaları yeniden okunur. Bu, değiştirilme zamanına (mtime) göre önbelleklenir.
  - Transcript, `findTranscript` ve `readTranscriptTail` ile okunur. Bu da yol ve mtime'a göre önbelleklenir.
- **Her 10 saniyede:**
  - `loadAgents` çağrılır,
  - farklı her cwd için `repoInfo` hesaplanır.
  - Bu ikisi `Task.detached` içinde çalışır, ana thread'i bloklamaz.
- Session kümesi, iki kaynağın birleşimidir: agents listesi ve son 24 saatte olay günlüğü olan session'lar. `paths.isInternal(cwd:)` için doğru dönen session'lar listeden çıkarılır.
- Her session için `SessionInputs` → `buildSnapshot` adımı uygulanır. Ardından `shouldKeep` filtresi, `sortForDisplay` ve `findConflicts` çalışır.
- `transitions` ile üretilen her bildirim `UNNotificationRequest` olarak gönderilir.
- Açılışta, 7 günden eski olay ve durum dosyaları silinir.
- `ask`:
  - O session'ın `status` ve `dialogue` bilgileriyle `buildAskPrompt` çağrılır, ardından `runAsk` çalışır.
  - `claude` bulunamazsa şu metin döner: "claude bulunamadı".
  - Hata olursa şu metin döner: "Cevap alınamadı: <hata>".

**`PanelView`:**
- Panel yaklaşık 380 pt genişliğinde olur.
- Başlıkta "Session Radar" yazar.
- Çakışma varsa en üstte turuncu bir şerit gösterilir: `Çakışma: <adA> ↔ <adB> · <dosyalar>`.
- **Session satırı:** renkli bir durum noktası ve etiket, ad, `repoName · branch`, görev, eylem, ilerleme (`3/7`) ve göreli süre (`RelativeDateTimeFormatter`).
  - `topicSummary` sonucunda bir konu varsa satırda `Konu: <current>` görünür.
  - Açık konu sayısı sıfırdan büyükse yanına `· <n> açık konu` eklenir.
- **Satıra tıklanınca açılan detay:** neden, aşama, sıradaki adım, checklist (✓ / ○), not ya da sorun, bekleyen dosyalar.
- **Konu akışı bölümü:** Detayda "Konu akışı" başlığı altında `topics` eskiden yeniye dikey bir akış olarak gösterilir. Öğeler ince bir dikey çizgiyle birbirine bağlanır.
  - `active`: dolu nokta, vurgu rengi ve kalın yazı.
  - `open`: boş nokta ve "açık" etiketi.
  - `done`: ✓ işareti ve ikincil renk.
  - Konu listesi yoksa bu bölüm gösterilmez.
- **Soru alanı:** `TextField("Bu session'a soru sor…")` ve "Sor" düğmesi bulunur. Cevap beklenirken `ProgressView` gösterilir, cevap gelince metin olarak yazılır.
- Liste boşsa "Açık session yok" yazar.
- Altta "Çık" düğmesi bulunur.

**`Resources/Info.plist`:**
- `CFBundleIdentifier` `co.eventpal.session-radar`
- `CFBundleName` / `CFBundleExecutable` `SessionRadar`
- `LSUIElement` `true`
- `LSMinimumSystemVersion` `14.0`
- `CFBundleShortVersionString` `0.1.0`
- `CFBundleVersion` `1`

**`scripts/build-app.sh` (`set -euo pipefail`):**
1. `swift build -c release` çalıştırılır.
2. `build/SessionRadar.app/Contents/MacOS/` klasörüne `SessionRadar` ve `radar-hook` kopyalanır. `Contents/` klasörüne `Info.plist` kopyalanır.
3. `codesign --force --deep -s - build/SessionRadar.app` ile imzalanır.
4. Script `--install` ile çalıştırılırsa ayrıca:
   - Çalışan uygulama varsa kapatılır: `pkill -x SessionRadar || true`.
   - `/Applications/SessionRadar.app` silinip yerine yenisi kopyalanır.
   - `/Applications/SessionRadar.app/Contents/MacOS/SessionRadar install` çalıştırılır.
   - Uygulama `open` ile başlatılır.

**`README.md`:** Kurulum (`scripts/build-app.sh --install`), kaldırma (`/Applications/SessionRadar.app/Contents/MacOS/SessionRadar uninstall`, ardından uygulamanın silinmesi) ve verilerin nerede durduğu. En fazla 15 satır.

- [ ] **Step 1: Write `Package.swift` change, `main.swift`, `RadarStore.swift`, `PanelView.swift`, `Info.plist`, `build-app.sh`, `README.md`.**

- [ ] **Step 2: Derle ve tüm testleri çalıştır**

Run: `swift build -c release && swift test`
Expected: Derleme başarılı, tüm testler PASS.

- [ ] **Step 3: Kur ve hook'ların eklendiğini doğrula**

Run: `scripts/build-app.sh --install && python3 -I -c 'import json,os; d=json.load(open(os.path.expanduser("~/.claude/settings.json"))); print(sorted(d["hooks"])); print([r for r in d["permissions"]["allow"] if "session-radar" in r])' && ls ~/.claude/settings.json.session-radar.bak`

Expected:
- Hook listesinde 8 olayın hepsi var,
- izin listesinde 2 kural var,
- yedek dosyası var,
- `theme`, `model` ve diğer anahtarlar yerinde.

- [ ] **Step 4: Olay akışını gerçek bir session'la doğrula** (küçük bir kota harcaması)

Run: `mkdir -p /tmp/radar-smoke && cd /tmp/radar-smoke && git init -q 2>/dev/null; claude -p "Bu klasörde merhaba.txt dosyası oluştur ve içine 'merhaba' yaz." --allowedTools Write && ls ~/.session-radar/events/ && tail -3 ~/.session-radar/events/*.jsonl | head -20`

Expected:
- Yeni session'ın günlüğünde `SessionStart`, `UserPromptSubmit`, `PreToolUse` (`Write`, `/tmp/radar-smoke/merhaba.txt`), `PostToolUse` ve `Stop` olayları var.
- Günlükte dosya içeriği ("merhaba") geçmiyor.

- [ ] **Step 5: Hook süresini ölç**

Run: `echo '{"hook_event_name":"PreToolUse","session_id":"t-1","tool_name":"Read"}' | SESSION_RADAR_HOME=/tmp/radar-time /usr/bin/time -p /Applications/SessionRadar.app/Contents/MacOS/radar-hook; rm -rf /tmp/radar-time`
Expected: `real` süresi 0,05 saniyenin altında.

- [ ] **Step 6: Kaldırma ve yeniden kurulum turu**

Run: `/Applications/SessionRadar.app/Contents/MacOS/SessionRadar uninstall && python3 -I -c 'import json,os; d=json.load(open(os.path.expanduser("~/.claude/settings.json"))); print("hooks" in d, [r for r in d.get("permissions",{}).get("allow",[]) if "session-radar" in r])' && /Applications/SessionRadar.app/Contents/MacOS/SessionRadar install`

Expected:
- Kaldırmadan sonra `False []` yazdırılır. Kurulumdan önce `hooks` anahtarı yoktu, bu yüzden tamamen kalkmış olmalı.
- Ardından kurulum tekrar başarılı olur.

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "feat: menü çubuğu uygulaması, paketleme ve kurulum"
```

- [ ] **Step 8: Onur'un elle doğrulayacakları (teslimde kullanıcıya listelenir)**
  1. Menü çubuğunda simge görünüyor ve panel açık session'ları listeliyor.
  2. Yeni bir terminalde `claude` açılıp tool gerektiren bir iş verildiğinde satır yaklaşık 2 saniye içinde "Çalışıyor" oluyor ve eylemi gösteriyor.
  3. İzin istendiğinde satır "Seni bekliyor" oluyor, bildirim geliyor ve rozet artıyor. Tur bitince "işini bitirdi" bildirimi geliyor.
  4. Çok adımlı bir işte durum dosyası oluşuyor ve panelde görev ile ilerleme görünüyor. Session'a konu değiştirtince konu akışında eski konu "kapandı" ya da "açık" olarak kalıyor, yeni konu "şu anki" olarak ekleniyor.
  - Not: Kurulumdan önce açılmış session'lar yeniden başlatılana kadar hook olayı göndermeyebilir. Bu durumda yalnızca `claude agents` ve transcript bilgisiyle görünürler.
  - Not: Kurulum, session'ların `~/.session-radar/status/` klasörüne izin sormadan yazmasına izin verir. Başka hiçbir yer için izin eklenmez.
  5. "Bu session ne yapıyordu?" sorusuna Türkçe bir cevap geliyor.
  6. Aynı repoda iki session aynı dosyayı düzenleyince çakışma şeridi çıkıyor ve bildirim geliyor.
