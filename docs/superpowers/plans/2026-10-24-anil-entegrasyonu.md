# Anıl Entegrasyonu Uygulama Planı

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Paylaşılan Eventpal repolarında karşı tarafın canlı konusunu agent'a bildirmek (sahiplik uyarısı) ve upstream'e gelen yeni commit'leri bildirim + "önce pull" ile haber vermek.

**Architecture:**
- **Uygulama (`RadarStore` + yeni `TeamSync` actor'ü):** 30 sn'de bir çalışır.
  - Kendi sahiplik kayıtlarını Supabase'e yazar ve karşı tarafınkileri okur.
  - Paylaşılan checkout'larda `git fetch` ve gelen commit kontrolü yapar.
  - Sonucu tek bir yerel dosyaya, `~/.session-radar/team/state.json`'a yazar.
- **`radar-hook`:** Ağa hiç çıkmaz. Yalnızca bu dosyayı ve session başına bir "iletildi" dosyasını okur, `additionalContext` ya da tek seferlik `deny` üretir.
- **Mantık yeri:** Tüm mantık `RadarCore`'daki saf fonksiyonlarda durur ve test edilir. Uygulama tarafındaki kod ince kalır.

**Tech Stack:** Swift 6.4, SwiftPM, SwiftUI (`Settings` sahnesi), Foundation `URLSession` (Supabase REST / PostgREST), `/usr/bin/git`, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-24-anil-entegrasyonu-design.md`

## Global Constraints

**Platform ve doğrulama**
- Swift 6.4, SwiftPM, `platforms: [.macOS(.v14)]`. Liquid Glass yalnızca `if #available(macOS 26, *)` içinde kullanılır.
- Yeni bağımlılık eklenmez. Supabase, `URLSession` ve PostgREST REST uçlarıyla konuşulur.
- Mevcut 122 test geçmeye devam eder ve `swift build -c release` hatasız biter.
- Kod stili mevcut koda uyar: tanımlayıcılar İngilizce, yorumlar ve arayüz metni Türkçe, yorum yoğunluğu düşük.

**Kod yerleşimi**
- Supabase'le konuşan kodun tamamı `Sources/RadarCore/Supabase.swift` dosyasında durur. Protokol ya da soyutlama katmanı kurulmaz.
- Hook ağa çıkmaz ve karşı taraftan gelen metni komut ya da yol olarak kullanmaz.
- Hook olay listesi (`radarHookEvents`) değişmez. SessionStart'ın düz metin çıktısı korunur. Diğer olaylar JSON `hookSpecificOutput` biçimini kullanır.

**Paylaşılan veri**
- Dışarıya yalnızca şu alanlar gider: ad, session id, repo anahtarı, branch, şu anki konu, açık konu başlıkları, çalışıyor/boşta, son istek zamanı, `updated_at`.
- Prompt metni, konu özeti, dosya adı ya da içeriği hiçbir zaman Supabase'e gitmez.
- Konu başlıkları tek satırdır ve en fazla 80 karakterdir. Ad en fazla 40 karakterdir. Bu sınır hem gönderirken hem alırken uygulanır.

**Zaman sınırları**
- Sahiplik sınırı: son kullanıcı isteğinden bu yana `8 * 3600` sn. Bu süre geçen kayıt yazılmaz, alınırsa da yok sayılır.
- Bayat kayıt: `updated_at` 300 sn'den eskiyse yok sayılır.
- Bayat yerel durum: `state.json` 300 sn'den eskiyse hook ekipten hiçbir şey üretmez.

**Kurulum ve kişisel alanlar**
- `~/.claude/settings.json` yalnızca kurulum betiğiyle, yedek alınarak ve birleştirme yapılarak değiştirilir. Testler gerçek dosyalara dokunmaz; geçici `RadarPaths(root:)` kullanılır.
- Subagent'lar `~/.claude`, `~/.session-radar` ve `/Applications`'a dokunmaz, uygulamayı kurmaz, ağa (Supabase) istek atmaz.
- Eventpal'in canlı Supabase projesi ve `eventpal-supabase` MCP araçları kullanılmaz.

**Commit**
- Görev başına tek commit, Türkçe mesaj. Mesajın sonunda şu satır yer alır: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`

**Ruling (spec'ten sapma):**
- **Karar:** Supabase oturumu Keychain yerine 0600 izinli `~/.session-radar/team/auth.json` dosyasında tutulur.
- **Neden:** Uygulama ad-hoc imzalı. Keychain'in erişim izni koda bağlı olduğu için her yeniden derlemeden sonra bir Keychain izin penceresi çıkar.
- **Yanlışsa maliyeti:** Tek bir dosyayı Keychain'e taşımak.

## Review Focus

1. **Ham prompt sızıntısı.** Durum dosyası ve gruplanmış konusu olmayan bir session hiçbir kayıt üretmemeli. `SessionSnapshot.task` ve `currentTopic`, son prompt'un ilk satırına düşer; bu alanlar asla kaynak olarak kullanılmaz. (Task 1, `noClaimWithoutStatusOrTopic`)
2. **Postgres zaman damgaları.** `2026-10-24T10:00:00.123456+00:00` biçimi (mikro saniye ve `+00:00`) çözülemezse karşı tarafın kayıtları sessizce kaybolur. (Task 4, `fetchOthersDecodesPostgresTimestamps`)
3. **Uygulama kapalı ya da çökmüş.** `state.json` eskidiğinde hook, ekip notu ya da push reddi üretmemeli. SessionStart metni de kurulu hâliyle birebir aynı kalmalı. (Task 2, `staleStateIsIgnored`)
4. **Git'in kenar durumları.** Upstream yok, HEAD detached, remote'a ulaşılamıyor ya da yalnızca yerel commit'ler ileride. Bu durumların hiçbirinde haber çıkmamalı, `fetch` de takılıp kalmamalı. (Task 3, `noIncomingWithoutUpstreamOrDetached`, `fetchFailsOnUnreachableRemote`)
5. **Karşı taraftan gelen tuhaf başlık.** Satır sonu, kontrol karakteri, `"`, `</veri>`, 500 karakter ya da emir kipi içeren bir başlık, notu bozmamalı ve tırnağın dışına taşmamalı. (Task 1, `claimTextIsSanitized`; Task 2, `noteSanitizesIncomingTitles`)

---

### Task 1: Sahiplik kaydı (`TeamClaim`, `buildClaims`)

**Files:**
- Create: `Sources/RadarCore/Team.swift`
- Modify:
  - `Sources/RadarCore/Topics.swift`: `oneLine` artık `private` değil, `internal` olur.
  - `Sources/RadarCore/Models.swift`: `SessionSnapshot` yapısına `statusUpdatedAt: Date? = nil` eklenir.
  - `Sources/RadarCore/Snapshot.swift`: `SessionInputs` yapısına `statusAt: Date?` eklenir (init'te son parametre, varsayılanı `nil`); `buildSnapshot` bu değeri `statusUpdatedAt`'e aktarır.
  - `Sources/SessionRadar/RadarStore.swift`: `Engine.tick`, `statuses[c.id]?.mtime` değerini `statusAt` olarak geçirir.
- Test: `Tests/RadarCoreTests/TeamTests.swift`

**Interfaces:**
- Produces:
```swift
public struct TeamClaim: Codable, Equatable, Sendable {
    public var ownerId: String?        // owner_id; sunucu doldurur
    public var ownerName: String       // owner_name
    public var sessionId: String       // session_id
    public var repoKey: String         // repo_key
    public var branch: String?
    public var topic: String
    public var openTopics: [String]    // open_topics
    public var working: Bool
    public var lastRequestAt: Date     // last_request_at
    public var updatedAt: Date?        // updated_at
}
public let claimMaxAge: TimeInterval = 8 * 3600
/// tek satır, kontrol karakteri yok, `"` → `'`, en fazla max karakter
func teamText(_ s: String, max: Int) -> String
public func buildClaims(_ sessions: [SessionSnapshot], histories: [String: SessionHistory],
                        owner: String, shared: Set<String>, now: Date) -> [TeamClaim]
```

**Kurallar (`buildClaims`):**
- **Kayıt üretme koşulları** (hepsi aynı anda sağlanmalı):
  - session `alive`,
  - `repoKey` değeri `shared` içinde,
  - `lastRequestAt = histories[id]?.requests.last?.at` var ve `now - lastRequestAt < claimMaxAge`.
- **`topic` seçimi:**
  1. `statusUpdatedAt > lastRequestAt` ise `status?.task`.
  2. Yoksa `histories[id]?.topics` içindeki son `state == "active"` konunun başlığı.
  3. İkisi de yoksa kayıt üretilmez.
- **Alanların doldurulması:**
  - `openTopics`: `state == "open"` olan konuların başlıkları, en fazla 5 tane.
  - Bütün metinler `teamText` ile kırpılır: başlıklar en fazla 80, ad en fazla 40 karakter.
  - `working`, `state == .working` olduğunda true olur.

- [ ] **Step 1: Write the failing tests** (`snap(...)` ve `history(...)` yardımcılarını test dosyasında tanımla)

```swift
@Test func claimUsesFreshStatusTaskOverTopic()        // status 10:05, son istek 10:00 → topic == status.task
@Test func claimFallsBackToActiveTopicWhenStatusStale() // status 09:00, son istek 10:00 → topic == aktif konu başlığı
@Test func noClaimWithoutStatusOrTopic() {
    // snapshot.task ve currentTopic "gizli prompt metni" (son prompt'tan), status nil, konu yok
    #expect(buildClaims([s], histories: [s.id: h], owner: "Onur", shared: [repo], now: now).isEmpty)
}
@Test func noClaimForUnsharedDeadOrOldSessions() {
    // shared dışı → [], alive false → [], son istek 8 sa + 1 sn önce → [], 8 sa − 1 sn önce → 1 kayıt
}
@Test func claimTextIsSanitized() {
    // başlık "a\"b\nc" + 200 × "x" → "a'b c…" tek satır, count <= 80; ad 60 karakter → count <= 40; 7 açık konu → 5
}
@Test func teamClaimEncodesSnakeCase() {
    // JSONEncoder çıktısı "session_id", "repo_key", "open_topics", "last_request_at", "owner_name" anahtarlarını içerir
}
```

- [ ] **Step 2:** `swift test --filter TeamTests`. Beklenen: derleme hatası (`buildClaims` tanımlı değil).
- [ ] **Step 3:** Yukarıdaki imzaları ve dosya değişikliklerini uygula. `teamText`, `oneLine`'ı çağırır ve ardından `"` karakterlerini `'` ile değiştirir.
- [ ] **Step 4:** `swift test`. Beklenen: hepsi geçer (122 + yeniler).
- [ ] **Step 5:** Commit: `Ekip: sahiplik kaydı (TeamClaim, buildClaims)`

---

### Task 2: Yerel ekip durumu ve hook

**Files:**
- Create: `Sources/RadarCore/TeamHook.swift`
- Modify:
  - `Sources/RadarCore/Models.swift`: `RadarPaths`'e `teamDir` (`root/team`), `teamStateFile` (`team/state.json`), `teamSettingsFile` (`team/settings.json`), `teamAuthFile` (`team/auth.json`) ve `teamDelivered(_ sid:)` (`team/delivered/<sid>.json`) eklenir. `prepareDirectories`, `teamDir` klasörünü de oluşturur.
  - `Sources/RadarCore/Topics.swift`: `saveTopicFile`'daki "0600 geçici dosya + rename" adımı `writeAtomically(_ data: Data, to url: URL) throws` adıyla dışarı çıkarılır. Bu fonksiyon üst klasörü 0700 izinle oluşturur. `saveTopicFile` artık onu kullanır.
  - `Sources/RadarCore/HookRecord.swift`: `runHook` güncellenir.
- Test: `Tests/RadarCoreTests/TeamHookTests.swift`

**Interfaces:**
- Consumes: Task 1'deki `TeamClaim`, `claimMaxAge` ve `teamText`.
- Produces:
```swift
public struct TeamPush: Codable, Equatable, Sendable { public var head: String; public var note: String }
public struct TeamSessionRef: Codable, Equatable, Sendable { public var repo: String; public var root: String; public var branch: String? }
public struct TeamState: Codable, Equatable, Sendable {
    public var writtenAt: Date
    public var roots: [String: String]          // checkout kökü -> repo anahtarı
    public var sessions: [String: TeamSessionRef]
    public var claims: [String: [TeamClaim]]    // repo anahtarı -> karşı tarafın kayıtları
    public var pushes: [String: TeamPush]       // checkout kökü -> bekleyen push
}
public struct TeamDelivered: Codable, Equatable, Sendable { public var claimsKey: String?; public var pushHead: String? }
public struct TeamSettings: Codable, Equatable, Sendable {
    public var name = ""; public var email = ""; public var enabled = false; public var sharedRepos: [String] = []
}
public let teamStaleAfter: TimeInterval = 300
public func readJSON<T: Decodable>(_ type: T.Type, from url: URL) -> T?      // iso8601 tarih; bozuk/yok → nil
public func writeJSON<T: Encodable>(_ value: T, to url: URL) throws          // iso8601, writeAtomically
public func composeTeamState(now: Date, sessions: [SessionSnapshot], shared: Set<String>,
                             others: [TeamClaim], pushes: [String: TeamPush]) -> TeamState
public func teamNote(repoName: String, claims: [TeamClaim], now: Date) -> String?
public func teamRule(repoName: String) -> String
public struct TeamHookResult: Equatable, Sendable { public var context: String?; public var deny: String?; public var delivered: TeamDelivered }
public func teamHook(_ e: HookEvent, state: TeamState?, delivered: TeamDelivered, now: Date) -> TeamHookResult
```

**`composeTeamState`:**
- `roots` ve `sessions`, yalnızca `repoKey ∈ shared` olan ve `repoRoot` değeri bulunan session'lardan oluşur.
- `claims`, `others` listesinin `repoKey`'e göre gruplanmış ve `shared`'e göre süzülmüş hâlidir.
- `pushes` içinde yalnızca `roots` içinde bulunan kökler kalır.

**`teamHook`:**
- **Yok sayma:** `state == nil` ise ya da `now - writtenAt > teamStaleAfter` ise boş sonuç döner ve `delivered` değişmez.
- **Repo eşleme:** Önce `state.sessions[e.sessionId]` kullanılır. Yoksa `e.cwd`, `roots` anahtarlarından birine eşitse ya da o anahtarın `"/"` ile devamıysa kullanılır. Birden çok kök eşleşirse en uzun olan seçilir. Hiçbiri eşleşmezse boş sonuç döner.
- **Kayıtları süzme:** O repoya ait kayıtlardan yalnızca şunlar kalır:
  - `now - lastRequestAt < claimMaxAge`,
  - `updatedAt` yok ya da `now - updatedAt < teamStaleAfter`.
- **`claimsKey`:** Kalan kayıtlardaki `ownerName|sessionId|topic|openTopics` değerleri sıralanıp birleştirilir. Kayıt kalmadıysa `nil` olur.
- **Olaya göre davranış:**
  - **`SessionStart`:**
    - `context = teamRule(...)` + (not varsa `"\n\n"` + not),
    - `delivered.claimsKey = claimsKey`.
  - **`UserPromptSubmit` / `PostToolUse`:**
    - `claimsKey != nil` ve `claimsKey != delivered.claimsKey` ise `context = not`.
    - Her durumda `delivered.claimsKey = claimsKey`.
  - **`PreToolUse`:**
    - **Engellenen tool'lar:** `Edit`, `Write`, `MultiEdit`, `NotebookEdit`, ya da `target`'ında `git ` ile birlikte ` commit` veya ` push` geçen bir `Bash` çağrısı.
    - **Koşul:** `state.pushes[ref.root]` var ve `head != delivered.pushHead`.
    - **Sonuç:** `deny = push.note` ve `delivered.pushHead = head`.

**`teamRule`** metni (aynen):
```
Ekip: Bu repo (<repoName>) ekip arkadaşlarınla ortak. Session Radar, karşı tarafın canlı session'larındaki konuları "Ekip notu" ile bildirir.
- Kullanıcının istediği iş ekip notundaki bir konuyla aynı ya da çok yakınsa, işe girmeden kullanıcıya söyle ve devam edip etmeyeceğini sor. Kullanıcı devam de derse devam et.
- "Push notu" gelirse dosya düzenlemeden ve commit'e geçmeden önce `git pull --rebase --autostash` çalıştır. Çakışma çıkarsa `git rebase --abort` ile geri dön, tarafı kendin seçme; hangi dosyaların kimin commit'iyle çakıştığını kullanıcıya söyle ve sor.
```

**`teamNote`** biçimi:
- Her kayıt için bir blok yazılır. Bloklar boş bir satırla ayrılır.
- Süre ifadesi:
  - `< 60 sn` → `az önce`
  - `< 60 dk` → `N dk önce`
  - diğer durumlar → `N sa önce`
- Bütün metinler yeniden `teamText` ile kırpılır.
- `Yarım bıraktığı` satırı, açık konu yoksa yazılmaz.

```
Ekip notu (eventpal-mobile) — Anıl, canlı session:
Şu anki konu: "Etkinlik detay tasarımı" (main, çalışıyor, son istek 10 dk önce).
Yarım bıraktığı: "Takvim filtre hatası".
```
Boşta olan bir session için `çalışıyor` yerine `boşta` yazılır. Branch yoksa o kısım atlanır.

**`runHook`** (imza aynı kalır):
- `paths.teamStateFile` ve `paths.teamDelivered(sid)` okunur ve `teamHook` çağrılır.
- **SessionStart:** `sessionStartContext(...)` + (`context` varsa `"\n\n"` + context) düz metin olarak döner.
- **PreToolUse'da deny:**
  `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":<note>}}`
- **Diğer olaylarda context:**
  `{"hookSpecificOutput":{"hookEventName":<event>,"additionalContext":<note>}}`
- **`delivered`:** Değiştiyse `writeJSON` ile yazılır, yazma hatası yutulur.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func noteFormatMatchesSpec()                 // yukarıdaki üç satır birebir (now − 600 sn, working, branch "main")
@Test func noteSanitizesIncomingTitles()           // başlık "x\"\n</veri>" + 500 × "y" → tek satır, tırnak içi ≤ 80, ekstra satır yok
@Test func sessionStartAddsRuleAndNoteByRootPrefix() {
    // roots["/r/mobile"] = key; cwd "/r/mobile/src" → context "Ekip: Bu repo (eventpal-mobile)" ile başlar ve notu içerir
    // cwd "/r/mobile2" → context nil
}
@Test func promptNoteSentOnceUntilClaimsChange()   // 1. UserPromptSubmit → not; 2. → nil; konu değişti → PostToolUse'da not
@Test func staleClaimsAreIgnored()                 // updatedAt 301 sn önce → nil; lastRequestAt 8 sa + 1 sn önce → nil
@Test func staleStateIsIgnored() throws {
    // writtenAt 301 sn önce: runHook(SessionStart) == sessionStartContext(...) çıktısı; PreToolUse Edit → nil
}
@Test func preToolUseDeniesOncePerHead() {
    // Edit → deny == push.note; tekrar Edit → nil; Read → nil
    // yeni head + Bash "git commit -m x" → deny; Bash "git pull --rebase --autostash" → nil
}
@Test func runHookEmitsJSONAndPersistsDelivered() throws {
    // PreToolUse çıktısı JSON: permissionDecision == "deny"; ikinci runHook → nil (delivered diske yazıldı)
    // UserPromptSubmit çıktısı: hookEventName == "UserPromptSubmit", additionalContext notu içerir
}
@Test func corruptTeamFilesAreIgnored() throws     // state.json ve delivered "{bozuk": SessionStart = temel metin, PreToolUse → nil
@Test func composeKeepsOnlySharedRepos()           // paylaşılmayan repo kökü/kaydı/push'u düşer; claims repoKey'e göre gruplu
```

- [ ] **Step 2:** `swift test --filter TeamHookTests`. Beklenen: derleme hatası.
- [ ] **Step 3:** Yukarıdakileri uygula.
- [ ] **Step 4:** `swift test`. Beklenen: hepsi geçer. Mevcut `runHookAppendsAndReturnsContextOnlyOnSessionStart` testi değişmeden geçmeli.
- [ ] **Step 5:** Commit: `Ekip: yerel durum dosyası ve hook notları`

---

### Task 3: Gelen commit'ler ve push haberi

**Files:**
- Modify:
  - `Sources/RadarCore/Git.swift`: `run(...)` fonksiyonuna `environment` ek anahtarları ve `timeout` parametreleri eklenir. Mevcut çağrılar aynı kalır.
  - `Sources/RadarCore/TeamHook.swift`: push metinleri buraya yazılır.
- Test: `Tests/RadarCoreTests/GitTests.swift` (mevcut yardımcıları kullan), `Tests/RadarCoreTests/TeamHookTests.swift`

**Interfaces:**
- Consumes: Task 2'deki `TeamPush`, Task 1'deki `teamText`.
- Produces:
```swift
public struct IncomingPush: Equatable, Sendable {
    public var upstream: String      // "origin/main"
    public var head: String          // upstream ucu sha
    public var count: Int
    public var authors: [String]     // en yeniden eskiye, tekrarsız
    public var latestAt: Date        // upstream ucunun committer zamanı
    public var files: [String]       // HEAD...upstream değişen dosyalar
}
public func fetchUpstream(cwd: String, git: String = "/usr/bin/git", timeout: TimeInterval = 30) -> Bool
public func incomingPush(cwd: String, git: String = "/usr/bin/git") -> IncomingPush?
public func pushNote(repoName: String, push: IncomingPush, timeZone: TimeZone = .current) -> String
public struct PushSighting: Equatable, Sendable {
    public var root: String; public var repoName: String; public var branch: String
    public var push: IncomingPush; public var overlap: Int
}
public func pushNotifications(_ s: [PushSighting], notified: Set<String>) -> (notes: [RadarNotification], notified: Set<String>)
```

**`fetchUpstream`:**
- Komut: `git fetch --quiet --no-tags --no-recurse-submodules`
- Ortam: `GIT_TERMINAL_PROMPT=0`, `GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=10"`
- Sıfır ile çıkarsa true döner.

**`incomingPush`:**
1. `rev-parse --abbrev-ref @{upstream}` başarısız olursa `nil` döner. Upstream yoksa ya da HEAD detached ise bu adım başarısız olur.
2. `merge-base --is-ancestor @{upstream} HEAD` başarılıysa `nil` döner.
3. Aksi hâlde alanlar şöyle doldurulur:
   - `count`: `rev-list --count HEAD..@{upstream}`
   - `authors`: `log --format=%an HEAD..@{upstream}`
   - `latestAt`: `log -1 --format=%ct @{upstream}`
   - `files`: `diff --name-only -z HEAD...@{upstream}` (`parseNulPaths`)
- Yazara göre süzme yapılmaz.

**`pushNote`** biçimi (aynen). Biçim kuralları:
- Yazarlar `teamText(max: 40)` ile kırpılır. En fazla 3 yazar yazılır, fazlası ` +n` olarak eklenir.
- En fazla 3 dosya yazılır, fazlası ` +n` olarak eklenir.
- Saat `HH:mm` biçimindedir ve `latestAt` değerinden alınır.

```
Push notu (eventpal-mobile): origin/main dalında yerelde olmayan 2 commit var (Anıl Eren Candan, 14:32). Değişen dosyalar: a.ts, b.ts, c.ts +2. Devam etmeden önce `git pull --rebase --autostash` çalıştır; çakışma çıkarsa `git rebase --abort` ile geri dön ve kullanıcıya sor.
```

**`pushNotifications`:**
- Kimlik: `"push:\(root):\(head)"`. Bu kimlik `notified` içindeyse bildirim atlanır.
- Başlık: `"\(repoName) · \(branch): \(count) yeni commit"`.
- Gövde: yazarlar. `overlap > 0` ise sonuna `" · senin değiştirdiğin \(overlap) dosyaya dokunuyor"` eklenir.

- [ ] **Step 1: Write the failing tests** (geçici bare remote + iki klon; klon B'de `user.name "Anıl"`)

```swift
@Test func incomingDetectsRemoteCommitsAndAuthors() throws {
    // B b.txt commit + push; A: fetchUpstream == true; incomingPush(A): upstream "origin/main", count 1,
    // authors ["Anıl"], files ["b.txt"]
}
@Test func noIncomingWhenUpToDateOrOnlyAhead() throws   // A pull sonrası → nil; A'da yalnızca yerel commit → nil
@Test func noIncomingWithoutUpstreamOrDetached() throws // upstream'siz yeni branch → nil; `checkout --detach` → nil
@Test func fetchFailsOnUnreachableRemote() throws       // remote "/nonexistent/x.git" → false
@Test func pushNoteMatchesSpec()                        // 5 dosya, 1 yazar, UTC 14:32 → yukarıdaki metin birebir
@Test func pushNotificationsOncePerHead()               // aynı sighting ikinci kez → bildirim yok; yeni head → bildirim; overlap metni
```

- [ ] **Step 2:** `swift test --filter GitTests`. Beklenen: derleme hatası.
- [ ] **Step 3:** Yukarıdakileri uygula.
- [ ] **Step 4:** `swift test`. Beklenen: hepsi geçer.
- [ ] **Step 5:** Commit: `Ekip: gelen commit tespiti ve push haberi`

---

### Task 4: Supabase istemcisi ve şema

**Files:**
- Create: `Sources/RadarCore/Supabase.swift`, `supabase/schema.sql`
- Test: `Tests/RadarCoreTests/SupabaseTests.swift`

**Interfaces:**
- Consumes: Task 1'deki `TeamClaim` (CodingKeys snake_case), Task 2'deki `readJSON` ve `writeJSON`.
- Produces:
```swift
public struct SupabaseConfig: Equatable, Sendable { public var url: URL; public var anonKey: String }
public struct AuthSession: Codable, Equatable, Sendable {
    public var accessToken: String; public var refreshToken: String; public var expiresAt: Date; public var userId: String
}
public enum SupabaseError: Error, Equatable { case http(Int, String), badResponse }
public typealias HTTPTransport = @Sendable (URLRequest) async throws -> (Data, URLResponse)
public struct SupabaseClient: Sendable {
    public init(config: SupabaseConfig, transport: @escaping HTTPTransport = { try await URLSession.shared.data(for: $0) })
    public func signIn(email: String, password: String, now: Date) async throws -> AuthSession
    /// süresine 60 sn'den az kaldıysa yeniler, yoksa aynısını döner
    public func authorized(_ s: AuthSession, now: Date) async throws -> AuthSession
    /// benim kayıtlarımı upsert eder, listede olmayan benim kayıtlarımı siler
    public func publish(_ claims: [TeamClaim], as s: AuthSession) async throws
    public func fetchOthers(as s: AuthSession, since: Date) async throws -> [TeamClaim]
}
```

**İstekler:**
- **Ortak başlıklar:** Her istekte `apikey: <anonKey>` bulunur. Oturumlu isteklere `Authorization: Bearer <accessToken>` eklenir, gövdeli isteklere `Content-Type: application/json`.
- **Giriş ve yenileme:**
  - `signIn`: `POST /auth/v1/token?grant_type=password`, gövde `{"email","password"}`.
    - Yanıttaki `access_token`, `refresh_token`, `expires_in` ve `user.id` alanları okunur.
    - `expiresAt = now + expires_in`.
  - `authorized` içindeki yenileme: `POST /auth/v1/token?grant_type=refresh_token`, gövde `{"refresh_token"}`.
- **`publish`:**
  1. Kayıt varsa: `POST /rest/v1/claims?on_conflict=owner_id,session_id` gönderilir.
     - Başlık: `Prefer: resolution=merge-duplicates,return=minimal`.
     - Gövde: kayıt dizisi; her kayıtta `owner_id = s.userId`.
  2. Ardından her durumda: `DELETE /rest/v1/claims?owner_id=eq.<uid>&session_id=not.in.(<id1>,<id2>)` gönderilir. Kayıt yoksa sorgu yalnızca `owner_id=eq.<uid>` olur.
- **`fetchOthers`:**
  - İstek: `GET /rest/v1/claims?select=*&owner_id=neq.<uid>&updated_at=gte.<since ISO8601, UTC>`.
  - Tarih çözümü: kesirli saniyeli ve kesirsiz ISO8601 biçimlerinin ikisi de kabul edilir (`+00:00` dahil).
- **Hatalar:** 2xx dışındaki yanıtlar `SupabaseError.http(status, gövdenin ilk 200 karakteri)` olur.

**`supabase/schema.sql`** (aynen bu adlar):
```sql
create table public.claims (
  owner_id uuid not null default auth.uid() references auth.users on delete cascade,
  owner_name text not null check (char_length(owner_name) <= 40),
  session_id text not null check (session_id ~ '^[A-Za-z0-9-]{1,64}$'),
  repo_key text not null check (char_length(repo_key) <= 200),
  branch text check (char_length(branch) <= 200),
  topic text not null check (char_length(topic) <= 80),
  open_topics text[] not null default '{}' check (cardinality(open_topics) <= 5),
  working boolean not null,
  last_request_at timestamptz not null,
  updated_at timestamptz not null default now(),
  primary key (owner_id, session_id)
);
alter table public.claims enable row level security;
create policy claims_read on public.claims for select to authenticated using (true);
create policy claims_insert on public.claims for insert to authenticated with check (owner_id = auth.uid());
create policy claims_update on public.claims for update to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy claims_delete on public.claims for delete to authenticated using (owner_id = auth.uid());
-- upsert'te updated_at yenilensin
create or replace function public.touch_claims() returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;
create trigger claims_touch before insert or update on public.claims for each row execute function public.touch_claims();
```

- [ ] **Step 1: Write the failing tests** (sahte `transport` istekleri bir diziye kaydeder ve hazır yanıt döner)

```swift
@Test func signInBuildsPasswordGrantAndParsesSession() async throws  // URL, apikey, gövde; expiresAt == now + 3600, userId
@Test func publishUpsertsWithOwnerAndDeletesOthers() async throws {
    // istek 1: POST, query "on_conflict=owner_id,session_id", Prefer başlığı, gövdede "owner_id":"u1" ve "session_id":"s1"
    // istek 2: DELETE, query "owner_id=eq.u1&session_id=not.in.(s1,s2)"
}
@Test func publishEmptyDeletesAllMine() async throws                 // tek istek: DELETE "owner_id=eq.u1"
@Test func fetchOthersDecodesPostgresTimestamps() async throws {
    // "2026-10-24T10:00:00.123456+00:00" ve "2026-10-24T10:00:00+00:00" → doğru Date; query "owner_id=neq.u1" içerir
}
@Test func httpErrorSurfaces() async throws                          // 401 → SupabaseError.http(401, …)
@Test func authorizedRefreshesNearExpiry() async throws              // expiresAt now+30 → refresh isteği; now+3600 → istek yok
```

- [ ] **Step 2:** `swift test --filter SupabaseTests`. Beklenen: derleme hatası.
- [ ] **Step 3:** Yukarıdakileri uygula. Bu görevde gerçek ağ isteği atılmaz.
- [ ] **Step 4:** `swift test`. Beklenen: hepsi geçer.
- [ ] **Step 5:** Commit: `Ekip: Supabase istemcisi ve şema`

---

### Task 5: Uygulamada ekip döngüsü (`TeamSync`)

**Files:**
- Create: `Sources/SessionRadar/TeamSync.swift`
- Modify:
  - `Sources/SessionRadar/RadarStore.swift`: döngüye bağlanır. `Engine.prune` ayrıca `team/delivered` klasörünü de temizler (7 gün).
- Test: Yok, çünkü uygulama hedefi test edilmiyor. Mantık Task 1–4'teki test edilmiş fonksiyonlarda duruyor.

**Interfaces:**
- Consumes:
  - Task 1: `buildClaims`
  - Task 2: `composeTeamState`, `TeamSettings`, `readJSON`, `writeJSON`, `RadarPaths.team*`
  - Task 3: `fetchUpstream`, `incomingPush`, `pushNote`, `pushNotifications`, `PushSighting`
  - Task 4: `SupabaseClient`, `AuthSession`, `SupabaseConfig`
- Produces (Task 6 bunları kullanır):
```swift
actor TeamSync {
    init(paths: RadarPaths, config: SupabaseConfig?)
    func step(sessions: [SessionSnapshot], histories: [String: SessionHistory], now: Date) async
        -> (notifications: [RadarNotification], down: Bool)
    func signIn(email: String, password: String) async -> String?   // hata metni, başarıda nil
    func signOut()
}
// RadarStore'a eklenenler:
var team: TeamSettings           // değişince paths.teamSettingsFile'a yazılır
var sharingDown = false
var teamSignedIn = false
var teamConfigured: Bool         // Info.plist'te SupabaseURL ve SupabaseAnonKey var mı
func teamSignIn(email: String, password: String) async -> String?
func teamSignOut()
```

**`step` adımları:**
1. Ayarlar `teamSettingsFile`'dan okunur.
   - `!enabled` ya da `sharedRepos` boşsa `teamStateFile` silinir ve `([], false)` döner.
2. **Push takibi:**
   - Kapsam: canlı session'ı olan ve `repoKey ∈ shared` olan her `repoRoot`.
   - `fetchUpstream` en fazla 180 sn'de bir çalışır. `incomingPush` her adımda çalışır, çünkü yerel ve ucuzdur. İkisi de `Task.detached` içinde çağrılır.
   - Her gelen commit için:
     - `pushNote(...)` metniyle bir `TeamPush` oluşturulur.
     - Bir `PushSighting` oluşturulur. Bunun `overlap` değeri, o kökteki session'ların `pendingFiles` birleşiminin `push.files` ile kesişim sayısıdır.
3. **Kayıtları paylaşma:**
   - Önce `claims = buildClaims(..., owner: settings.name, ...)` hesaplanır.
   - Oturum (`auth.json`) ve `config` varsa: `authorized` → `publish(claims)` → `fetchOthers(since: now - 300)`. Yenilenen oturum `auth.json`'a yazılır.
   - Hata olursa `down = true` ve `others = []`. Başarılı olursa `down = false`.
   - Oturum yoksa, `config` yoksa ya da `settings.name` boşsa kayıt paylaşılmaz ve `down = false` kalır.
4. `writeJSON(composeTeamState(...), to: teamStateFile)`.
5. `pushNotifications(sightings, notified:)` çağrılır. Bildirilen kimlikler (`notified`) actor'de tutulur.

**`RadarStore`:**
- `start()` içindeki döngüde `n % 30 == 0` olduğunda `teamStep` çalışır. `slowRunning` gibi, aynı anda tek bir iş çalışmasını sağlayan bir bayrakla korunur.
- Dönen bildirimler `post` ile gönderilir. `sharingDown` yalnızca değiştiğinde atanır.
- `config`, `Bundle.main` Info.plist'indeki `SupabaseURL` ve `SupabaseAnonKey` anahtarlarından okunur. Biri eksik ya da boşsa `nil` olur.

- [ ] **Step 1:** `TeamSync`'i ve `RadarStore` bağlantısını uygula.
- [ ] **Step 2:** `swift build` ve `swift build -c release`. Beklenen: uyarı ve hata yok.
- [ ] **Step 3:** `swift test`. Beklenen: hepsi geçer.
- [ ] **Step 4:** Raporda, `step`'in yukarıdaki 5 adımı hangi satırlarda yaptığını listele.
- [ ] **Step 5:** Commit: `Ekip: uygulamada eşitleme döngüsü`

---

### Task 6: Ayarlar penceresi ve "paylaşım kapalı" işareti

**Files:**
- Create: `Sources/SessionRadar/TeamSettingsView.swift`
- Modify:
  - `Sources/SessionRadar/main.swift`: `body` içine `Settings { TeamSettingsView(store: store) }` eklenir.
  - `Sources/SessionRadar/PanelView.swift`: üstteki `Menu`'ye `Divider()` öncesine `SettingsLink { Text("Ayarlar…") }` eklenir. Başlıktaki işaret de bu dosyada.
  - `Sources/SessionRadar/SessionWindow.swift`: toolbar'daki işaret.

**Interfaces:**
- Consumes: Task 5'te `RadarStore`'a eklenen alanlar ve fonksiyonlar.

**Arayüz:**
- **Ayarlar penceresi:** `Form { … }.formStyle(.grouped)` ile kurulur ve şu bölümlerden oluşur.
  - **"Sen":** `TextField("Adın", text: $store.team.name)`.
  - **"Hesap":**
    - Giriş yapılmamışsa: e-posta alanı, `SecureField` ile parola alanı ve "Giriş yap" düğmesi. Düğme `store.teamSignIn` çağrısını yapar; hata metni kırmızı değil, ikincil renkte gösterilir.
    - Giriş yapılmışsa: e-posta ve "Çıkış yap".
    - `teamConfigured == false` ise bölüm yalnızca "Sunucu ayarlanmamış" metnini gösterir.
  - **"Paylaşım":**
    - `Toggle("Çakışma uyarılarını aç", isOn: $store.team.enabled)`.
    - Altında `store.sessions` içinden tekrarsız `repoKey` / `repoName` çiftleri listelenir; her biri için bir `Toggle(repoName)` vardır ve bu toggle `sharedRepos` dizisine ekleme ya da çıkarma yapar.
    - En altta ikincil renkte açıklama: "Yalnızca seçtiğin repolarda ad, branch ve konu başlığı paylaşılır."
- **Ayarlar penceresinin açılması:** Ayarlar penceresi menü çubuğu uygulamasında arkada açılabilir. Bu yüzden `SettingsLink`'e `.simultaneousGesture(TapGesture().onEnded { NSApp.activate() })` eklenir.
- **"Paylaşım kapalı" işareti:**
  - Ne zaman: `store.team.enabled && store.sharingDown`.
  - Nerede: panel başlığında ve pencere toolbar'ında.
  - Nasıl: `Image(systemName: "person.2.slash")`, `.foregroundStyle(.secondary)` ve `.help("Paylaşım kapalı: sunucuya ulaşılamıyor")`.
  - Bunun dışında karşı tarafa dair hiçbir şey gösterilmez.

- [ ] **Step 1:** Görünümleri ve bağlantıları uygula.
- [ ] **Step 2:** `swift build -c release`. Beklenen: uyarı ve hata yok.
- [ ] **Step 3:** Görsel kontrol: Önceki görevlerdeki gibi, commit'lenmeyen ve görünmez bir `NSHostingView` penceresiyle `TeamSettingsView`'ın açık ve koyu temada PNG'sini üret (`ImageRenderer` boş çiziyor). PNG yollarını raporda ver. Snapshot kodunu commit'leme.
- [ ] **Step 4:** `swift test`. Beklenen: hepsi geçer.
- [ ] **Step 5:** Commit: `Ekip: ayarlar penceresi ve paylaşım işareti`

---

### Task 7: Dağıtım (zip ve Anıl için kurulum)

**Files:**
- Modify:
  - `scripts/build-app.sh`
  - `.gitignore`: `config/supabase.env` eklenir.
- Create: `scripts/kur.sh`, `docs/anil-kurulum.md`

**`build-app.sh`:**
- **Supabase ayarı:** `config/supabase.env` dosyası varsa (`SUPABASE_URL=…` ve `SUPABASE_ANON_KEY=…` satırları) değerler paketteki `Contents/Info.plist`'e `plutil -replace SupabaseURL -string …` ve `plutil -replace SupabaseAnonKey -string …` ile yazılır. Bu işlem `codesign`'dan önce yapılır. Dosya yoksa atlanır.
- **`--zip`:**
  - Evrensel derleme yapılır: `swift build -c release --arch arm64 --arch x86_64`. Bin yolu aynı bayraklarla `--show-bin-path`'ten alınır.
  - `lipo -archs` çıktısında iki mimari de görünmezse betik hata verip durur.
  - `ditto -c -k --keepParent` ile `build/SessionRadar.zip` üretilir. Zip içinde `SessionRadar.app` ve `kur.sh` bulunur.
  - `--install` davranışı değişmez.

**`kur.sh`** (zip'in açıldığı klasörde çalışır):
1. `sw_vers -productVersion` < 14 ise hata verip durur.
2. `command -v claude` yoksa uyarı verir ama devam eder. Varsa `claude --version` çıktısını yazdırır.
3. `xattr -dr com.apple.quarantine SessionRadar.app` çalıştırır.
4. `pkill -x SessionRadar || true` çalıştırır.
5. Uygulamayı `/Applications`'a kopyalar.
6. `/Applications/SessionRadar.app/Contents/MacOS/SessionRadar install` çalıştırır.
7. `open /Applications/SessionRadar.app` çalıştırır.

**`docs/anil-kurulum.md`:** Kısa Türkçe kurulum adımları:
1. Zip'i aç.
2. `bash ~/Downloads/SessionRadar/kur.sh` komutunu çalıştır.
3. Menü çubuğu → `…` → Ayarlar: adını yaz, Onur'un verdiği e-posta ve parolayla giriş yap, Eventpal repolarını işaretle.

Kaldırmak için: `SessionRadar uninstall`.

- [ ] **Step 1:** Yukarıdakileri uygula.
- [ ] **Step 2:** Sahte bir `config/supabase.env` oluştur (`SUPABASE_URL=https://example.supabase.co`, `SUPABASE_ANON_KEY=test`), ardından `./scripts/build-app.sh --zip` çalıştır. Beklenenler:
  - `lipo -archs build/SessionRadar.app/Contents/MacOS/SessionRadar` çıktısı hem `x86_64` hem `arm64` içerir,
  - `plutil -p build/SessionRadar.app/Contents/Info.plist` iki anahtarı da gösterir,
  - `unzip -l build/SessionRadar.zip` içinde `SessionRadar.app/` ve `kur.sh` görünür,
  - sahte env dosyası en sonunda silinir.
- [ ] **Step 3:** `bash -n scripts/kur.sh`. Beklenen: hata yok. `kur.sh` çalıştırılmaz, çünkü `/Applications`'a dokunur.
- [ ] **Step 4:** `swift test`. Beklenen: hepsi geçer.
- [ ] **Step 5:** Commit: `Ekip: zip dağıtımı ve Anıl için kurulum`

---

### Task 8: Canlıya alma (ana session yapar, Onur'un onayıyla; subagent değil)

- [ ] **Supabase projesi:**
  - Onur'un `oer@eventpal.co` hesabındaki ücretsiz organizasyonda yeni bir proje aç. Eventpal'in canlı projesini kullanma.
  - `supabase/schema.sql`'i SQL Editor'de çalıştır.
  - Auth ayarlarında yeni kaydı kapat ("Allow new users to sign up" kapalı).
  - Onur ve Anıl için iki kullanıcı oluştur.
- [ ] **Uygulama ayarı:** Proje URL'si ve anon anahtarı `config/supabase.env`'e yazılır. Bu dosya commit'lenmez.
- [ ] **Onur'un makinesi:**
  - `./scripts/build-app.sh --install` çalıştır.
  - Ayarlar'da ad, giriş ve repolar (`eventpal-mobile`, `onlyeventV2`, `onlyevent-scraper-v3`, `eventpal-image-service`) ayarlanır.
  - Kontrol: `~/.session-radar/team/state.json` oluşuyor mu, Supabase tablosunda Onur'un satırları var mı?
- [ ] **Anıl'ın makinesi:**
  - `./scripts/build-app.sh --zip` çalıştır ve zip'i Anıl'a gönder.
  - Anıl'dan `sw_vers` ve `claude --version` çıktılarını iste.
  - Anıl `kur.sh` çalıştırır ve giriş yapar.
- [ ] **Uçtan uca deneme:**
  1. Onur mobilde bir konu açar.
  2. Anıl aynı repoda benzer bir istek yazar. Beklenen: agent'ın uyarması.
  3. Anıl main'e push eder. Beklenen: Onur'a bildirim gelmesi ve Onur'un agent'ının bir sonraki düzenlemeden önce pull etmesi.
