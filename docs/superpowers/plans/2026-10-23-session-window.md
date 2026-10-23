# Session Penceresi ve Konu Geçmişi Uygulama Planı

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Her session'ın kullanıcı isteklerini konuşma kaydından çıkarıp Haiku ile konu başlıkları altında gruplamak ve bunu ayrı bir macOS penceresinde zaman çizgisi olarak göstermek.

**Architecture:** `RadarCore` iki yeni dosya kazanır:
- `History.swift`: transcript'ten istekleri artımlı ve parça parça okur.
- `Topics.swift`: konu modeli, Haiku prompt'u, cevap ayrıştırma ve birleştirme, dosyada saklama, gruplama zamanlayıcısı kararı.

Uygulamadaki `Engine` actor'ü geçmişi tutar ve bir seferde tek bir gruplama işini `runAsk` ile çalıştırır. Yeni `SessionWindow`, `NavigationSplitView` ile listeyi ve hikâyeyi gösterir. Session'ların kendi yazdığı `topics` alanı kaldırılır.

**Tech Stack:** Swift 6.4, SwiftPM, SwiftUI (`Window`, `NavigationSplitView`), Swift Testing. Üçüncü taraf bağımlılık yok.

**Spec:** `docs/superpowers/specs/2026-10-23-session-window-design.md` (üst tasarım: `docs/superpowers/specs/2026-10-23-session-radar-design.md`)

## Global Constraints

- `RadarCore` yalnızca `Foundation` import eder. Swift 6 dil modu kullanılır, derleme uyarısız olmalı. Üçüncü taraf paket eklenmez.
- **Haiku çağrıları** yalnızca mevcut `runAsk(prompt:claudePath:paths:timeout:)` fonksiyonuyla yapılır. Bu fonksiyon `env -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN … -p --model haiku --tools "" --no-session-persistence --setting-sources project` komutunu çalıştırır. Başka bir çağrı yolu eklenmez.
- **Kota kuralları:**
  - Aynı anda en fazla bir gruplama işi çalışır.
  - Bir session için yeni turların tetiklediği gruplamalar arasında en az 120 saniye geçer.
  - Birikmiş isteklerin parçaları arka arkaya işlenir; bekleme uygulanmaz.
  - Tek çağrıda istek metinleri en fazla 500 karakter, cevap metinleri en fazla 300 karakter olur. Toplam yaklaşık 30.000 karakteri geçmez.
- **Ana thread:** Transcript okuma, JSON ayrıştırma ve Haiku çağrıları ana thread'de yapılmaz.
- **Hatalı model çıktısı:** Haiku cevabı ayrıştırılamaz ya da doğrulamayı geçemezse mevcut konu listesi aynen kalır. Yeniden deneme yalnızca 120 saniyelik bekleme kuralıyla yapılır.
- **Konu dosyaları:** `~/.session-radar/topics/<sessionId>.json` yolunda, `0600` izinle, atomik olarak yazılır. Klasörün izni `0700` olur. Mevcut 7 günlük temizliğe dahil edilir.
- **UI metinleri Türkçe olur.**
  - Konu durum etiketleri: `active` → "Şu anki". Session kapanmışsa `active` → "Son konu". `open` → "Açık kaldı", `done` → "Kapandı". Bilinmeyen değerler "Açık kaldı" olarak gösterilir.
  - "n açık konu" sayısı yalnızca `open` konuları sayar.
- Commit mesajları `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` satırıyla biter. Kod yorumları seyrek ve Türkçe olur.

## Review Focus

1. **Haiku cevabı çoğu zaman JSON'u kod bloğu içinde ya da önünde bir açıklama metniyle verir. Bazen de bozuk JSON döner.** Beklenen: geçerli JSON varsa çıkarılsın, yoksa eski konular korunsun. Test: Task 2, `parseResponseToleratesFencesAndProse` ve `parseResponseRejectsGarbage`.
2. **Claude yazarken transcript'in son satırı yarım olabilir. Ayrıca 200 MB'lık dosyalar var.** Beklenen: istek kaybolmasın, iki kez sayılmasın, bellek dosya boyutu kadar büyümesin. Test: Task 1, `readRequestsStopsAtPartialLine` ve `readRequestsContinuesIndexAcrossReads` (küçük `chunkSize` ile).
3. **Transcript'teki gürültü satırları.** Arka plan görev bildirimleri, slash komut satırları, `!` komutları, compaction özetleri, subagent satırları ve kesme işaretleri istek sayılmamalı. Yapıştırılmış içerik sayılmalı. Test: Task 1, `requestFilterMatchesRealNoise`.
4. **Haiku iki konuyu "active" işaretlerse ya da en son istek "active" olmayan bir konuya düşerse.** Beklenen: en son isteğin konusu "active" olur, diğer active konular "open" olur. Test: Task 2, `mergeNormalizesActive`.
5. **Transcript yeniden yazılır ya da küçülürse.** Beklenen: o session'ın konu listesi silinir ve baştan gruplanır. Test: Task 1, `readRequestsDetectsTruncation`. Engine bu bayrağa göre konu listesini sıfırlar (Task 4).

**Spec'ten bilinçli bir sapma (Claude'un kararı):** Spec, Haiku'nun tam konu listesini `requests` dizileriyle döndürmesini söylüyor. Plan bunun yerine Haiku'dan iki şey istiyor: güncellenmiş konu başlıkları ve durumları, ayrıca yalnızca **yeni** isteklerin hangi konuya atandığı (`assign`). Birleştirme yerelde yapılır. Bunun nedeni şu: 100'den fazla isteği olan session'larda modelin eski numaraları eksiksiz tekrar yazması güvenilmez, bu da doğrulamayı sık sık düşürür. Diskte saklanan model, spec'teki gibi `requests` dizileri olan tam konu listesidir.

---

## Dosya Yapısı

```
Sources/RadarCore/History.swift      — yeni: Request, HistoryCursor, readRequests (artımlı, parça parça)
Sources/RadarCore/Topics.swift       — yeni: Topic, TopicFile, SessionHistory, prompt, ayrıştırma, birleştirme, parçalama, saklama, zamanlayıcı kararı, etiket
Sources/RadarCore/Models.swift       — değişir: RadarPaths.topicsDir/topicFile ve hazırlık; SessionSnapshot.currentTopic/openTopics; TopicItem ve SessionStatus.topics kaldırılır
Sources/RadarCore/HookRecord.swift   — değişir: sessionStartContext metninden topics çıkar
Sources/RadarCore/Snapshot.swift     — değişir: SessionInputs.topics; buildSnapshot currentTopic/openTopics; eski topicSummary kaldırılır
Sources/SessionRadar/RadarStore.swift — değişir: geçmiş okuma, gruplama döngüsü, histories/selectedSessionId, topics temizliği
Sources/SessionRadar/SessionWindow.swift — yeni: pencere arayüzü
Sources/SessionRadar/PanelView.swift  — değişir: satırda yeni konu alanları, TopicFlow kaldırılır, "Tüm session'lar" düğmesi; AskBox paylaşılır
Sources/SessionRadar/main.swift       — değişir: Window sahnesi
Tests/RadarCoreTests/HistoryTests.swift, TopicsTests.swift — yeni
```

---

### Task 1: Transcript'ten istekleri artımlı okuma

**Files:**
- Create: `Sources/RadarCore/History.swift`
- Modify: `Sources/RadarCore/Models.swift` (`RadarPaths`)
- Test: `Tests/RadarCoreTests/HistoryTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct Request: Codable, Equatable, Sendable {
      public var index: Int          // 1'den başlar, session içinde ardışık
      public var text: String        // en fazla 2000 karakter
      public var at: Date?           // satırın "timestamp" alanı (ISO8601, kesirli saniye olabilir)
      public var reply: String?      // o turda Claude'un son text bloğu, en fazla 2000 karakter
      public init(index: Int, text: String, at: Date?, reply: String?)
  }
  public struct HistoryCursor: Codable, Equatable, Sendable {
      public var offset: UInt64 = 0
      public var nextIndex: Int = 1
      public init()
  }
  public struct HistoryRead: Equatable, Sendable {
      public var requests: [Request]      // bu okumada bulunan yeni istekler
      public var trailingReply: String?   // bu okumada, ilk yeni istekten ÖNCE görülen son Claude metni (bir önceki isteğe aittir)
      public var cursor: HistoryCursor
      public var truncated: Bool          // dosya cursor.offset'ten küçükse true; cursor sıfırlanır ve dosya baştan okunur
  }
  public func readRequests(_ url: URL, from cursor: HistoryCursor, chunkSize: Int = 4 << 20) -> HistoryRead
  // RadarPaths'e:
  public var topicsDir: URL                 // root/topics
  public func topicFile(_ sessionId: String) -> URL   // topics/<id>.json
  // prepareDirectories() topicsDir'i de 0700 oluşturur
  ```

**İstek filtresi** (spec'teki karar, birebir uygulanır):
- Satır `type == "user"` olmalı ve `message.content` string olmalı.
- Şu durumlarda satır istek sayılmaz:
  - `isMeta`, `isCompactSummary`, `isVisibleInTranscriptOnly` ya da `isSidechain` alanlarından biri `true` ise,
  - içerik baştaki boşluklar atıldıktan sonra `<` ile başlıyorsa,
  - içerik `[Request interrupted` ile başlıyorsa.
- İstisna: `<pasted_content` ile başlayan içerik istek sayılır.
- **Claude cevabı:** `type == "assistant"` satırlarındaki `text` bloklarından, bir sonraki isteğe kadar görülen sonuncusu.
  - `isSidechain` alanı `true` olan asistan satırları atlanır.

**Okuma kuralları:**
- Okuma `cursor.offset` noktasından başlar ve en fazla `chunkSize` baytlık parçalarla ilerler.
- Yalnızca son `\n` karakterine kadar olan kısım tüketilir. Yarım kalan son satır bir sonraki okumaya bırakılır.
- Her satırı JSON olarak ayrıştırmadan önce ham baytlarda `"type":"user"` ya da `"type":"assistant"` geçip geçmediğine bakılır. Asistan satırları için ayrıca `"type":"text"` aranır. Diğer satırlar ayrıştırılmadan atlanır.
- Kodun yanına şu yorum eklenir: `// ponytail: uygulama her açılışta transcript'i baştan tarar; çok büyük dosyalarda cursor+istekler diske yazılabilir`.

- [ ] **Step 1: Write the failing tests** (`HistoryTests.swift`; satırlar test içinde geçici dosyaya yazılır, `tempFile` Sources testlerinde zaten var)

```swift
func userLine(_ text: String, ts: String = "2026-10-23T01:11:49.379Z", extra: String = "") -> String {
    #"{"type":"user",\#(extra)"timestamp":"\#(ts)","message":{"role":"user","content":\#(jsonString(text))}}"#
}
func assistantText(_ text: String) -> String {
    #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":\#(jsonString(text))}]}}"#
}
@Test func requestFilterMatchesRealNoise() throws {
    let lines = [
        userLine("Login hatasını düzelt"),
        userLine("<task-notification>\n<task-id>x</task-id>"),
        userLine("<command-name>/clear</command-name>"),
        userLine("<local-command-stdout></local-command-stdout>"),
        userLine("<bash-input>ls</bash-input>"),
        userLine("This session is being continued from a previous conversation", extra: #""isCompactSummary":true,"#),
        userLine("meta", extra: #""isMeta":true,"#),
        userLine("alt görev", extra: #""isSidechain":true,"#),
        userLine("[Request interrupted by user]"),
        userLine("<pasted_content id=\"a\">log</pasted_content>"),
        #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"ok"}]}}"#,
    ]
    let r = readRequests(try tempFile(lines.joined(separator: "\n") + "\n"), from: HistoryCursor())
    #expect(r.requests.map(\.text) == ["Login hatasını düzelt", "<pasted_content id=\"a\">log</pasted_content>"])
    #expect(r.requests.map(\.index) == [1, 2])
    #expect(r.requests[0].at != nil)
}
@Test func replyIsLastAssistantTextOfTurn() throws {
    let r = readRequests(try tempFile([userLine("A"), assistantText("ilk"), assistantText("son"), userLine("B"), assistantText("B cevap")].joined(separator: "\n") + "\n"), from: HistoryCursor())
    #expect(r.requests.map(\.reply) == ["son", "B cevap"])
}
@Test func readRequestsStopsAtPartialLine() throws {
    let url = try tempFile(userLine("A") + "\n" + String(userLine("B").prefix(20)))
    let r = readRequests(url, from: HistoryCursor())
    #expect(r.requests.map(\.text) == ["A"] && r.cursor.nextIndex == 2)
}
@Test func readRequestsContinuesIndexAcrossReads() throws {
    let url = try tempFile(userLine("A") + "\n")
    let first = readRequests(url, from: HistoryCursor(), chunkSize: 64)
    let h = try FileHandle(forWritingTo: url); try h.seekToEnd()
    try h.write(contentsOf: Data((assistantText("A cevap") + "\n" + userLine("B") + "\n").utf8)); try h.close()
    let second = readRequests(url, from: first.cursor, chunkSize: 64)
    #expect(second.requests.map(\.index) == [2] && second.trailingReply == "A cevap")
}
@Test func readRequestsDetectsTruncation() throws {
    let url = try tempFile(userLine("A") + "\n" + userLine("B") + "\n")
    let first = readRequests(url, from: HistoryCursor())
    try (userLine("Yeni") + "\n").write(to: url, atomically: true, encoding: .utf8)
    let again = readRequests(url, from: first.cursor)
    #expect(again.truncated && again.requests.map(\.index) == [1] && again.requests[0].text == "Yeni")
}
```

`jsonString(_:)` yardımcısı JSON'a kaçışlı bir string literal üretir. `JSONEncoder` ile yazılır ve bu test dosyasında tanımlanır.

- [ ] **Step 2: Run** — `swift test --filter HistoryTests` → Expected: derleme hatası (`readRequests` tanımlı değil).
- [ ] **Step 3: Implement `History.swift` and the `RadarPaths` additions.**
- [ ] **Step 4: Run** — `swift test --filter HistoryTests` → Expected: PASS. Ardından `swift test` → tüm testler PASS.
- [ ] **Step 5: Gerçek veriyle duman testi** (yalnızca okuma)

`HistoryTests.swift`'e ortam değişkenine bağlı bir test eklenir: `@Test(.enabled(if: ProcessInfo.processInfo.environment["RADAR_BIG_TRANSCRIPT"] != nil)) func bigTranscriptSmoke()`. Bu test, değişkenin gösterdiği dosyada `readRequests` çalıştırır, istek sayısını ve süreyi `print` eder, istek sayısının 0'dan büyük olduğunu doğrular.

Run: `RADAR_BIG_TRANSCRIPT=/Users/onur/.claude/projects/-Users-onur-Desktop-Projeler-eventpal-mobile/1450babd-72d0-42f3-942b-aa88afa786ee.jsonl /usr/bin/time -l swift test --filter bigTranscriptSmoke 2>&1 | tail -25`

Expected:
- Test PASS olur, okuma süresi 20 saniyenin altında kalır.
- "maximum resident set size" 200 MB'ın (dosya boyutu) belirgin şekilde altında olur.
- [ ] **Step 6: Commit** — `git add -A && git commit -m "feat: transcript'ten istekleri artımlı okuma"`

---

### Task 2: Konu modeli, Haiku prompt'u, ayrıştırma, birleştirme ve saklama

**Files:**
- Create: `Sources/RadarCore/Topics.swift`
- Test: `Tests/RadarCoreTests/TopicsTests.swift`

**Interfaces:**
- Consumes: Task 1'deki `Request`.
- Produces:
  ```swift
  public struct Topic: Codable, Equatable, Sendable {
      public var id: Int; public var title: String; public var state: String  // "active" | "open" | "done"
      public var summary: String; public var requests: [Int]
      public init(id: Int, title: String, state: String, summary: String, requests: [Int])
  }
  public struct TopicFile: Codable, Equatable, Sendable {
      public var sessionId: String; public var grouped: Int; public var topics: [Topic]; public var updatedAt: Date
      public init(sessionId: String, grouped: Int, topics: [Topic], updatedAt: Date)
  }
  public struct SessionHistory: Equatable, Sendable {
      public var requests: [Request]; public var topics: [Topic]; public var grouping: Bool
      public init(requests: [Request], topics: [Topic], grouping: Bool)
  }
  public struct TopicResponse: Decodable, Equatable, Sendable {
      public struct Item: Decodable, Equatable, Sendable { public var id: Int; public var title: String; public var state: String; public var summary: String }
      public var topics: [Item]; public var assign: [String: Int]   // "istek no" -> konu id
  }
  public func chunkRequests(_ requests: [Request], maxChars: Int = 30_000) -> [[Request]]
  public func buildTopicPrompt(existing: [Topic], requests: [Request]) -> String
  public func parseTopicResponse(_ output: String) -> TopicResponse?
  public func mergeTopics(existing: [Topic], response: TopicResponse, newRequests: [Request]) -> [Topic]?
  public func loadTopicFile(_ url: URL) -> TopicFile?
  public func saveTopicFile(_ file: TopicFile, to url: URL) throws     // atomik, 0600
  ```

**Kurallar:**
- **`chunkRequests`:** Her isteğin maliyeti şöyle hesaplanır: `min(text.count, 500) + min(reply?.count ?? 0, 300) + 40`. Sıra korunur. Tek başına sınırı aşan bir istek kendi parçasında yer alır.
- **`buildTopicPrompt`:** Prompt'un tam metni builder'a bırakıldı. Ama aşağıdakilerin hepsini içermeli:
  - **Görev:** Bir Claude Code session'ında kullanıcının isteklerini konu başlıkları altında grupla.
  - **Mevcut konular:** Her biri `id`, `title`, `state`, `summary` ve istek numaralarının aralığıyla verilir.
  - **Yeni istekler:** Her biri `#index`, `HH:mm` biçiminde saat, ilk 500 karakteri ve Claude'un ilk 300 karakterlik cevabıyla verilir.
  - **Kurallar:**
    - Yalnızca JSON döndür, başka metin yazma.
    - Şema: `{"topics":[{"id":1,"title":"…","state":"active|open|done","summary":"…"}],"assign":{"12":1}}`.
    - Mevcut tüm konuları gerektiği gibi güncelleyerek döndür. Yeni bir konu gerekirse `id` değerini mevcut en büyük id'den büyük ver.
    - Her yeni istek numarasını `assign` içinde tam olarak bir konuya ata.
    - Başlıklar en fazla 6 kelime, özetler en fazla 3 cümle olsun ve Türkçe yazılsın.
    - Bir konunun işi bitmişse `done`, yarım kalıp sonra dönülecekse `open` olarak işaretle.
    - Başlıklar gereksiz yere değiştirilmesin.
- **`parseTopicResponse`:** Çıktıdaki ilk `{` ile son `}` arasını alır ve `JSONDecoder` ile çözer. Bu yolla kod blokları ve çevredeki açıklama metni tolere edilir. Çözülemezse `nil` döner.
- **`mergeTopics`:**
  - Şu durumlarda `nil` döner: yeni isteklerden biri `assign` içinde yoksa, var olmayan bir konu id'sine atanmışsa ya da yanıttaki bir konunun başlığı boşsa.
  - Aksi halde:
    1. Mevcut konuların başlık, durum ve özetleri yanıttaki aynı id'li öğeyle güncellenir. Yanıtta olmayan mevcut konu olduğu gibi kalır.
    2. Yeni id'ler yeni konu olarak eklenir.
    3. Atanan istek numaraları ilgili konunun `requests` listesine eklenir.
    4. Hiç isteği olmayan konular atılır.
    5. En büyük istek numarasını içeren konu `active` yapılır. Diğer `active` konular `open` olur. Bilinmeyen durum değerleri `open` olur.
    6. Konular ilk istek numaralarına göre sıralanır.

- [ ] **Step 1: Write the failing tests**

```swift
func req(_ i: Int, _ t: String = "istek") -> Request { Request(index: i, text: t, at: nil, reply: nil) }
@Test func parseResponseToleratesFencesAndProse() {
    let out = "İşte sonuç:\n```json\n{\"topics\":[{\"id\":1,\"title\":\"Giriş hatası\",\"state\":\"active\",\"summary\":\"Login düzeltildi.\"}],\"assign\":{\"1\":1}}\n```"
    #expect(parseTopicResponse(out)?.assign == ["1": 1])
}
@Test func parseResponseRejectsGarbage() {
    #expect(parseTopicResponse("Üzgünüm, yapamam.") == nil)
    #expect(parseTopicResponse("{\"topics\": 3}") == nil)
}
@Test func mergeAppendsNewRequestsAndTopics() throws {
    let existing = [Topic(id: 1, title: "Giriş", state: "active", summary: "s", requests: [1, 2])]
    let resp = try #require(parseTopicResponse(#"{"topics":[{"id":1,"title":"Giriş","state":"done","summary":"bitti"},{"id":2,"title":"Bildirim","state":"active","summary":"yeni"}],"assign":{"3":1,"4":2}}"#))
    let m = try #require(mergeTopics(existing: existing, response: resp, newRequests: [req(3), req(4)]))
    #expect(m.map(\.requests) == [[1, 2, 3], [4]] && m.map(\.state) == ["done", "active"])
}
@Test func mergeRejectsUnassignedOrUnknown() throws {
    let resp = try #require(parseTopicResponse(#"{"topics":[{"id":1,"title":"A","state":"active","summary":""}],"assign":{"3":1}}"#))
    #expect(mergeTopics(existing: [], response: resp, newRequests: [req(3), req(4)]) == nil)
    let bad = try #require(parseTopicResponse(#"{"topics":[{"id":1,"title":"A","state":"active","summary":""}],"assign":{"3":9}}"#))
    #expect(mergeTopics(existing: [], response: bad, newRequests: [req(3)]) == nil)
}
@Test func mergeNormalizesActive() throws {
    let resp = try #require(parseTopicResponse(#"{"topics":[{"id":1,"title":"A","state":"active","summary":""},{"id":2,"title":"B","state":"active","summary":""},{"id":3,"title":"C","state":"weird","summary":""}],"assign":{"1":1,"2":2,"3":3,"4":1}}"#))
    let m = try #require(mergeTopics(existing: [], response: resp, newRequests: [req(1), req(2), req(3), req(4)]))
    #expect(m.map(\.state) == ["active", "open", "open"])
}
@Test func chunkingRespectsBudget() {
    let long = (1...100).map { req($0, String(repeating: "x", count: 900)) }
    let chunks = chunkRequests(long, maxChars: 5_000)
    #expect(chunks.flatMap { $0 }.map(\.index) == Array(1...100))
    #expect(chunks.allSatisfy { $0.count * 540 <= 5_000 || $0.count == 1 })   // her istek 500 + 0 + 40
}
@Test func promptCarriesSchemaAndTruncates() {
    let p = buildTopicPrompt(existing: [], requests: [Request(index: 7, text: String(repeating: "a", count: 900), at: nil, reply: String(repeating: "b", count: 900))])
    #expect(p.contains("\"assign\"") && p.contains("#7") && !p.contains(String(repeating: "a", count: 501)) && !p.contains(String(repeating: "b", count: 301)))
}
@Test func topicFileRoundTripsWithPrivatePermissions() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".json")
    let f = TopicFile(sessionId: "s", grouped: 2, topics: [Topic(id: 1, title: "A", state: "active", summary: "", requests: [1, 2])], updatedAt: Date(timeIntervalSince1970: 1))
    try saveTopicFile(f, to: url)
    #expect(loadTopicFile(url) == f)
    #expect((try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int) == 0o600)
}
```

- [ ] **Step 2: Run** — `swift test --filter TopicsTests` → Expected: derleme hatası.
- [ ] **Step 3: Implement `Topics.swift`** (bu task'ta yalnızca yukarıdaki API'ler; zamanlayıcı ve etiket Task 3'te).
- [ ] **Step 4: Run** — `swift test --filter TopicsTests` ve ardından `swift test` → Expected: PASS.
- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: konu modeli, Haiku prompt'u ve birleştirme"`

---

### Task 3: Zamanlayıcı kararı, anlık görüntüde konu bilgisi, eski `topics` alanının kaldırılması

**Files:**
- Modify: `Sources/RadarCore/Topics.swift`, `Sources/RadarCore/Snapshot.swift`, `Sources/RadarCore/Models.swift`, `Sources/RadarCore/HookRecord.swift`
- Modify tests: `Tests/RadarCoreTests/SnapshotTests.swift` (`topicSummaryCountsOpen` kaldırılır), `Tests/RadarCoreTests/SourcesTests.swift` (`statusLoadingIsTolerant` içindeki `topics` beklentisi kaldırılır; fixture'daki `topics` anahtarı kalır ve yok sayıldığı doğrulanır)
- Test: `Tests/RadarCoreTests/TopicsTests.swift`

**Interfaces:**
- Consumes: Task 2'deki `Topic`.
- Produces:
  ```swift
  public struct GroupingCandidate: Equatable, Sendable {
      public var id: String; public var ungrouped: Int; public var state: SessionState; public var alive: Bool
      public var lastRunAt: Date?; public var lastRunLeftBacklog: Bool
      public init(id: String, ungrouped: Int, state: SessionState, alive: Bool, lastRunAt: Date?, lastRunLeftBacklog: Bool)
  }
  public func nextGroupingJob(_ candidates: [GroupingCandidate], selected: String?, now: Date, gap: TimeInterval = 120) -> String?
  public func topicStateLabel(_ state: String, sessionClosed: Bool) -> String
  public func currentTopicSummary(_ topics: [Topic]) -> (current: String?, open: Int)   // current: active başlık; open: "open" sayısı
  // SessionInputs: yeni alan `public var topics: [Topic]` (init parametresi, varsayılan [])
  // SessionSnapshot: yeni alanlar `public var currentTopic: String?`, `public var openTopics: Int`
  ```

**`nextGroupingJob` kuralları:**
- **Uygun aday:** Şu üç koşulun hepsini sağlayan aday.
  1. `ungrouped > 0`.
  2. Aday `selected` session ise, ya da (`alive` doğru ve `state != .working`) ise. Kapanmış ve seçili olmayan session'lar gruplanmaz.
  3. `lastRunAt == nil` ise, ya da `lastRunLeftBacklog` doğruysa, ya da son çalışmadan bu yana `gap` kadar süre geçtiyse.
- **Öncelik:** `selected` uygunsa önce o seçilir. Değilse uygun adaylardan dizide ilk sıradaki seçilir (çağıran taraf adayları görüntü sırasıyla verir).
- **`buildSnapshot`:**
  - `currentTopic` = `currentTopicSummary(topics).current`. Konu yoksa görev alanıyla aynı kuralla `lastPrompt` kullanılır (ilk satır, en fazla 80 karakter, kesilirse `…`).
  - `openTopics` = `currentTopicSummary(topics).open`.
- **Kaldırılanlar:**
  - `TopicItem`, `SessionStatus.topics`, eski `topicSummary(_:)`.
  - `sessionStartContext` metninden `topics` bölümü.
- **Yeni `sessionStartContext` metni** birebir şu olacak (`<YOL>` yerine `statusFile.path` gelir):

```
Session Radar: Kullanıcı session'larını bir menü çubuğu uygulamasından takip ediyor. Kod değişikliği ya da çok adımlı bir iş yapıyorsan durumunu Write tool ile şu dosyaya yaz (her seferinde dosyanın tamamını yeniden yaz):
<YOL>
Biçim: {"task":"…","why":"…","phase":"…","next":"…","todo":[{"text":"…","done":false}],"problems":[]}
Ne zaman: göreve başlarken, aşama değişince, iş bitince, bir sorun çıkınca veya çözülünce; her adımda değil. Alanlar Türkçe ve en fazla birer cümle olsun. Sorun çözülünce "problems" listesini boşalt. Basit soru-cevaplarda dosyayı yazma.
```

- [ ] **Step 1: Write the failing tests** (`TopicsTests.swift`'e eklenir)

```swift
func cand(_ id: String, _ n: Int, _ st: SessionState = .turnDone, alive: Bool = true, last: Date? = nil, backlog: Bool = false) -> GroupingCandidate {
    GroupingCandidate(id: id, ungrouped: n, state: st, alive: alive, lastRunAt: last, lastRunLeftBacklog: backlog)
}
@Test func schedulerRules() {
    let now = Date(timeIntervalSince1970: 1_000)
    #expect(nextGroupingJob([cand("a", 0), cand("b", 3)], selected: nil, now: now) == "b")
    #expect(nextGroupingJob([cand("a", 3, .working)], selected: nil, now: now) == nil)
    #expect(nextGroupingJob([cand("a", 3, .working)], selected: "a", now: now) == "a")
    #expect(nextGroupingJob([cand("a", 3, .closed, alive: false)], selected: nil, now: now) == nil)
    #expect(nextGroupingJob([cand("a", 3, last: now.addingTimeInterval(-60))], selected: nil, now: now) == nil)
    #expect(nextGroupingJob([cand("a", 3, last: now.addingTimeInterval(-60), backlog: true)], selected: nil, now: now) == "a")
    #expect(nextGroupingJob([cand("a", 3), cand("b", 3)], selected: "b", now: now) == "b")
}
@Test func labelsFollowSessionState() {
    #expect(topicStateLabel("active", sessionClosed: false) == "Şu anki")
    #expect(topicStateLabel("active", sessionClosed: true) == "Son konu")
    #expect(topicStateLabel("open", sessionClosed: false) == "Açık kaldı")
    #expect(topicStateLabel("done", sessionClosed: false) == "Kapandı")
    #expect(topicStateLabel("x", sessionClosed: false) == "Açık kaldı")
}
@Test func snapshotUsesTopicsThenLastPrompt() {
    let topics = [Topic(id: 1, title: "Eski", state: "open", summary: "", requests: [1]), Topic(id: 2, title: "Bildirimler", state: "active", summary: "", requests: [2])]
    func inputs(_ t: [Topic]) -> SessionInputs {
        SessionInputs(sessionId: "s", agent: nil, registry: nil, alive: true, seenAlive: true, activity: nil, status: nil,
                      transcript: TranscriptInfo(aiTitle: nil, lastPrompt: "Son istek", lastAction: nil, dialogue: []),
                      repo: nil, lastSeen: Date(), topics: t)
    }
    let a = buildSnapshot(inputs(topics))
    #expect(a.currentTopic == "Bildirimler" && a.openTopics == 1)
    let b = buildSnapshot(inputs([]))
    #expect(b.currentTopic == "Son istek" && b.openTopics == 0)
}
@Test func startContextHasNoTopics() {
    #expect(!sessionStartContext(statusFile: URL(fileURLWithPath: "/x/s.json")).contains("topics"))
}
```

`SessionInputs.init` parametre sırasını Task 3 belirler. Mevcut çağrı yerlerini (Engine, testler) derlenecek şekilde güncelle: `topics` son parametre olur ve varsayılanı `[]`'dir.

- [ ] **Step 2: Run** — `swift test --filter TopicsTests` → Expected: derleme hatası.
- [ ] **Step 3: Implement** — `Topics.swift`'e zamanlayıcı ve etiket. `Snapshot.swift`, `Models.swift` ve `HookRecord.swift` değişiklikleri. Eski testlerin güncellenmesi.
- [ ] **Step 4: Run** — `swift test` → Expected: tüm testler PASS, derleme uyarısız.
- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: gruplama zamanlayıcısı ve anlık görüntüde konu"`

---

### Task 4: Engine'de geçmiş ve gruplama döngüsü

**Files:**
- Modify: `Sources/SessionRadar/RadarStore.swift`

**Interfaces:**
- Consumes: Task 1'deki `readRequests` ve `HistoryCursor`. Task 2'deki `chunkRequests`, `buildTopicPrompt`, `parseTopicResponse`, `mergeTopics`, `loadTopicFile`, `saveTopicFile`, `SessionHistory`. Task 3'teki `nextGroupingJob`, `GroupingCandidate` ve `SessionInputs.topics`. Mevcut `runAsk`.
- Produces (pencerenin kullanacakları):
  ```swift
  // RadarStore (@MainActor @Observable)
  var histories: [String: SessionHistory]   // yalnızca değiştiğinde atanır
  var selectedSessionId: String?            // pencere yazar; zamanlayıcıda öncelik
  ```

**Kurallar:**
- **Session başına durum:** Engine her session için şunları tutar:
  - `cursor`,
  - `requests` (bellekte),
  - `TopicFile`'dan yüklenen `topics` ve `grouped`,
  - `lastRunAt`,
  - `lastRunLeftBacklog`,
  - `grouping` bayrağı.

  `TopicFile` session ilk kez görüldüğünde diskten yüklenir.
- **Her tick'te:** Her aday session için transcript yolu mevcut `transcript()` mantığıyla bulunur ve `readRequests` çağrılır.
  - `trailingReply` önceki son isteğin `reply` alanına yazılır.
  - `truncated` bayrağı gelirse `requests`, `topics` ve `grouped` sıfırlanır ve konu dosyası silinir.
  - Okuma tick'i bloklamamalı: büyük ilk okumalar Engine actor'ü içinde yapılır, ana thread'e dokunulmaz.
- **Gruplama döngüsü:** `RadarStore.tick()` sonrasında, çalışan bir gruplama işi yoksa:
  1. `engine.nextJob(selected:now:)` çağrılır. Bu, `nextGroupingJob` ile seçilen session'ın gruplanmamış isteklerinden **ilk parçayı** (`chunkRequests(...).first`), mevcut konularla kurulan prompt'u ve session id'yi döner.
  2. Store, `runAsk` ile Haiku'yu çağırır. Bu `Task` içinde çalışır, ana actor bloklanmaz.
  3. Sonuç `engine.finishJob(sessionId:output:)` ile işlenir.
     - Başarılıysa: `mergeTopics` uygulanır, `grouped` parça kadar artar, `TopicFile` kaydedilir, `lastRunLeftBacklog = (grouped < requests.count)` olur.
     - Hata, `nil` sonuç ya da doğrulama hatası olursa: konular değişmez, `lastRunLeftBacklog = false` olur.
     - Her iki durumda `lastRunAt = now` yazılır.
- **Aday bilgileri:**
  - `ungrouped` = `requests.count - grouped`.
  - `state` ve `alive` anlık görüntüden ve adaydan alınır.
  - Sıra `sortForDisplay` sırasıdır.
- `claude` bulunamazsa gruplama yapılmaz.
- `prune()`, 7 günden eski konu dosyalarını da siler.
- `histories` yalnızca listede olan session'lar için üretilir.

- [ ] **Step 1: Implement the Engine and RadarStore changes.**
- [ ] **Step 2: Build and test** — `swift build -c release && swift test` → Expected: derleme uyarısız, tüm testler PASS.
- [ ] **Step 3: Kur ve gerçek gruplamayı doğrula** (abonelik kotasından birkaç küçük Haiku çağrısı; kullanıcı onayladı)

Run: `scripts/build-app.sh --install`. Ardından en fazla 5 dakika boyunca 30 saniyede bir `ls -la ~/.session-radar/topics/` çalıştırılır. Dosya oluşunca şu çalıştırılır: `python3 -I -c 'import json,glob; f=sorted(glob.glob("/Users/onur/.session-radar/topics/*.json"))[0]; d=json.load(open(f)); print(d["grouped"], [(t["title"], t["state"], len(t["requests"])) for t in d["topics"]])'`

Expected:
- En az bir canlı ve çalışmıyor durumdaki session için konu dosyası oluşur.
- Başlıklar Türkçedir, en fazla bir konu `active` olur.
- `ls -ld ~/.session-radar/topics` çıktısı `drwx------` olur.
- `/usr/bin/log show --last 10m --predicate 'process == "SessionRadar"'` çıktısında çökme yoktur.

- [ ] **Step 4: Commit** — `git add -A && git commit -m "feat: geçmiş okuma ve Haiku ile konu gruplama döngüsü"`

---

### Task 5: Session penceresi ve panel değişiklikleri

**Files:**
- Create: `Sources/SessionRadar/SessionWindow.swift`
- Modify: `Sources/SessionRadar/main.swift`, `Sources/SessionRadar/PanelView.swift`

**Interfaces:**
- Consumes: Task 4'teki `RadarStore.histories` ve `selectedSessionId`. Task 3'teki `SessionSnapshot.currentTopic` / `openTopics` ve `topicStateLabel`. Mevcut `SessionState.label` / `color` ve `AskBox`.

**Kurallar:**
- **`main.swift`:** `MenuBarExtra`'nın yanına `Window("Session Radar", id: "sessions") { SessionWindow(store: store) }` eklenir. Varsayılan boyut 980×640 olur.
- **`PanelView`:**
  - Altta "Çık" düğmesinin soluna "Tüm session'lar" düğmesi eklenir. Bu düğme `openWindow(id: "sessions")` çağırır, ardından `NSApplication.shared.activate()` ile uygulamayı öne getirir.
  - Satırdaki konu satırı artık şöyle: `Konu: \(currentTopic)` ve `openTopics > 0` ise sonuna `· \(openTopics) açık konu`.
  - `TopicFlow` ve `status.topics` kullanımı kaldırılır.
  - `AskBox`, `private` olmaktan çıkarılır ve pencerede de kullanılır.
- **`SessionWindow` düzeni:** `NavigationSplitView` kullanılır.
  - **Kenar çubuğu:** `List(selection:)` ile `store.sessions` sırasında listelenir.
    - Her satırda durum noktası, ad, `currentTopic` (tek satır) ve durum etiketi bulunur.
    - Seçim `store.selectedSessionId` ile bağlanır.
    - Pencere açıldığında seçim yoksa ilk session seçilir.
  - **Detay alanı,** kaydırılabilir ve yukarıdan aşağıya:
    1. **Başlık:** ad, `repoName · branch` ve durum.
    2. **"Başlangıç":** ilk isteğin metni (en fazla 6 satır) ve tarih-saati.
    3. **"Konu akışı":**
       - Konular eskiden yeniye dikey bir zaman çizgisi üzerinde gösterilir. Solda nokta ve noktaları birleştiren dikey bir çizgi bulunur.
       - Her kartta başlık, `topicStateLabel(state, sessionClosed: session.state == .closed)` etiketi, zaman aralığı ve özet yer alır. Zaman aralığı, konunun isteklerinin en erken ve en geç `at` değerleridir, `HH:mm` ya da farklı günse `d MMM HH:mm` biçiminde.
       - `active` kart vurgulanır: vurgu rengi ve kalın başlık.
       - Karta tıklanınca o konuya ait istekler `#n · HH:mm · metin` biçiminde açılır. Metin en fazla 3 satır gösterilir.
       - Konu yoksa: "Konu başlıkları henüz çıkarılmadı" yazar, altında istekler gruplanmadan, aynı biçimde listelenir.
       - `history.grouping` doğruysa başlığın yanında küçük bir `ProgressView` ve "Gruplanıyor…" görünür.
    4. **"Şu an":**
       - `currentTopic`, son eylem (`action`),
       - durum dosyasından görev ve sıradaki adım,
       - checklist (✓ / ○),
       - sorunlar ya da not.
    5. **`AskBox`.**
  - **Hiç session yoksa:** detayda "Açık session yok" yazar.

- [ ] **Step 1: Implement `SessionWindow.swift` and the `main.swift` / `PanelView.swift` changes.**
- [ ] **Step 2: Build and test** — `swift build -c release && swift test` → Expected: derleme uyarısız, tüm testler PASS.
- [ ] **Step 3: Kur** — `scripts/build-app.sh --install` → Expected: uygulama çalışıyor (`pgrep -x SessionRadar`), `radar-hook` yerinde.
- [ ] **Step 4: Commit** — `git add -A && git commit -m "feat: session penceresi ve konu akışı"`
- [ ] **Step 5: Onur'un elle doğrulayacakları (teslimde listelenir)**
  1. Menü panelindeki "Tüm session'lar" düğmesi pencereyi açıyor ve pencere öne geliyor.
  2. Solda tüm session'lar görünüyor. Birini seçince sağda başlangıç, konu akışı ve "Şu an" bölümleri görünüyor.
  3. Kurulumdan önce açılmış bir session için konular birkaç dakika içinde oluşuyor. Bu sırada "Gruplanıyor…" görünüyor.
  4. Bir session'a yeni bir konuda iş verilip tur bitince yeni bir konu kartı ekleniyor ve önceki konunun durumu güncelleniyor.
  5. Konu kartına tıklayınca o konunun istekleri saatleriyle açılıyor.
