# Session Radar — Tasarım

Tarih: 2026-10-23 · Sahibi: Onur · Kullanıcılar: Onur ve Anıl

## Amaç ve neden

Onur ve Anıl aynı anda çok sayıda Claude Code session'ı çalıştırıyor (Onur'un makinesinde şu an 10'dan fazla). Terminallere bakarak takip etmek zor. Onur'un ihtiyaçları, önem sırasıyla:

1. **Tek bakışta:** Hangi session şu an çalışıyor, hangisi benden cevap bekliyor?
2. **Hatırlatma:** Terminale döndüğümde "bu session ne yapıyordu, bunu neden yapıyoruz, hangi aşamada, sırada ne var, ne kadar işi kaldı, sorun çıktı mı?" sorularının cevabı.
3. **Ekip farkındalığı:** Anıl'ın session'larını da aynı yerde görmek. Aynı projede aynı işi yapmamak, aynı dosyaları paralel değiştirip birbirimizi ezmemek, çakışan push'lardan kaçınmak.

Bunların bildirim olarak gelmesi isteniyor.

## Hedefler

1. **macOS menü çubuğu uygulaması.** Simgeye tıklanınca panel açılır, tekrar tıklanınca kapanır. Uygulama arka planda sürekli çalışır ve oturum açılışında kendiliğinden başlar. Panel canlıdır: bir durum değişikliği en geç birkaç saniyede görünür.
2. **Simge** beni bekleyen session sayısını gösterir.
3. **Session listesi** kişiye göre gruplanır (Onur / Anıl). Her satırda şunlar yer alır:
   - session adı,
   - proje (repo adı) ve branch,
   - durum: çalışıyor / seni bekliyor / tur bitti / sorun var / kapandı (tanımlar aşağıda, "Durum tanımları" bölümünde),
   - şu anki görev (kısa başlık),
   - şu anki eylem (ör. "`src/Home.tsx` düzenleniyor", "`npm test` çalışıyor"),
   - ilerleme (ör. 3/7),
   - son güncellemeden bu yana geçen süre.
4. **Detay görünümü:** neden yapıldığı, aşama, sıradaki adım, kalan işler (checklist) ve sorunlar.
   - **Konu akışı (Onur'un isteği, 2026-10-23):** Session'lar ilerledikçe konu değiştiriyor. Detay görünümü, session'ın başladığı konudan şu ana kadar geçtiği konuları sırayla bir akış olarak gösterir.
   - Her konu için durum belirtilir: şu anki / açık (yarım kaldı, dönülecek) / kapandı.
   - Satırda şu anki konu ve açık kalan konu sayısı görünür.
   - Konu listesini session'ın kendisi tutar *(Claude'un kararı)*.
5. **Soru sor:** Kendi session'larımdan birini seçip serbest metin bir soru sorarım ("ne yapıyordun, neden?"). Cevabı, o session'ın kaydını ve durum dosyasını okuyan ayrı bir Claude çağrısı verir. Session'ın kendisi bölünmez, ona mesaj gitmez.
6. **macOS bildirimleri** şu durumlarda gelir:
   - bir session soru sorduğunda ya da izin istediğinde,
   - bir session işini bitirdiğinde,
   - bir sorun çıktığında,
   - Anıl'la çakışma olduğunda (aşağıya bakınız).
7. **Çakışma uyarısı:** Aynı repoda (git remote adresine göre eşleştirilir) iki session'ın değiştirdiği dosyalar kesişirse uyarı verilir. Bu iki session Onur'un ve Anıl'ın olabilir, Onur'un kendi iki session'ı da olabilir. Tam tanım aşağıda, "Çakışma tanımı" bölümünde.
8. **Paylaşım:** Her iki kullanıcının uygulaması, session özetlerini ortak bir Supabase tablosuna yazar ve karşı tarafınkini Realtime ile dinler.

## Durum tanımları ve bildirimler *(Claude'un kararı)*

| Durum | Ne zaman | Simgedeki sayıya dahil mi | Bildirim |
|---|---|---|---|
| **çalışıyor** | `UserPromptSubmit` ile `Stop` arasında (Claude bir tur üzerinde çalışırken); ayrıca `Stop` geldiğinde `background_tasks` boş değilse, yani session arka plandaki bir işi bekliyorsa | hayır | yok |
| **seni bekliyor** | Bekleyen bir izin, elicitation ya da `agent_needs_input` olduğunda; veya `Stop` sonrasında son asistan mesajı kullanıcıya bir soru sorduğunda | **evet** | bir kez, durum başladığında |
| **tur bitti** | `Stop` geldiğinde ve soru olmadığında. Sıra kullanıcıdadır ama cevap beklenmiyordur. Tüm görevin bitip bitmediğini satırdaki checklist ilerlemesi gösterir. | hayır | her `Stop`'ta bir kez ("X işini bitirdi") |
| **sorun var** | Session durum dosyasına bir sorun yazdığında; session süreci çalışırken `SessionEnd` olmadan öldüğünde (boştayken kaybolan session "kapandı" sayılır); bir tur API hatası ya da rate limit nedeniyle bittiğinde (`StopFailure`); ya da kullanım limiti nedeniyle durakladığında (`quota_auto_resume_stale` / `quota_auto_resume_disabled`) | evet | bir kez |
| **kapandı** | `SessionEnd` geldiğinde veya session `claude agents --json` listesinden düştüğünde | hayır | yok |

- Kullanıcı session'a yeni bir mesaj yazınca, yani yeni bir `UserPromptSubmit` gelince, "seni bekliyor" ve "tur bitti" durumları kendiliğinden sona erer.
- Başarısız tool çağrıları (ör. hata veren bir test komutu) sorun sayılmaz. Bunlar Claude'un normal çalışmasının parçası.
- Bildirimler yalnızca durum değiştiğinde bir kez gönderilir, tekrarlanmaz. Bildirim sayısı kullanıcının session'lara mesaj yazma sıklığıyla sınırlı kalır.

## Çakışma tanımı *(Claude'un kararı)*

- **Bir session'ın dosyaları:** Session'ın yaşamı boyunca `Edit` / `Write` hook'larıyla dokunduğu dosyalardan, hâlâ **commit'lenmemiş ya da commit'lenip push'lanmamış** olanlar. Bu dosyalar `git status --porcelain` ile `git diff --name-only @{upstream}...HEAD` çıktısının birleşimiyle bulunur. Upstream yoksa remote'un varsayılan branch'ine göre bakılır.
- **Ne zaman sayılmaz olur:** Dosya push'landığında. Push'tan sonra değişiklik git'te görünür hâle gelir ve olası çakışmayı git'in kendisi yönetir.
- **Session bittiğinde:** Dosya hâlâ commit'lenmemiş veya push'lanmamışsa sayılmaya devam eder. Kişi bazında bir "bekleyen değişiklikler" kaydı olarak kalır ve satır kapansa bile çakışma kontrolüne dahil edilir.
- **Branch'ler:** Farklı branch'ler de çakışma sayılır, çünkü merge sırasında çakışırlar. Uyarıda iki tarafın branch'i de gösterilir.
- **Aynı klasördeki iki session:** Aynı checkout'ta (worktree değil) çalışan iki session aynı `git status`'u paylaşır. Bu durumda dosyalar session'lara yalnızca `Edit` / `Write` hook kayıtlarına göre atfedilir.
- **Paylaşılan alan:** Supabase'e session başına bu dosya listesi gider. Yollar repo köküne göre göreli tutulur.

## Kapsam dışı (v1)

- Uygulamadan session'a cevap yazmak, session başlatmak veya durdurmak. Cevap vermek için terminale gidilir. *(Claude'un kararı)*
- Anıl'ın session'larına soru sormak. Ham kayıt paylaşılmadığı için yalnızca paylaşılan özet görünür. *(Claude'un kararı)*
- WidgetKit widget'ı. Sık güncellenmek için tasarlanmadığından canlı takibe uygun değil.
- claude.ai/code bulut session'ları.
- Windows ve Linux.
- **Tailscale:** v1'de yok, ileride ikinci bir taşıma seçeneği olarak eklenecek. Bunun için Supabase'le konuşan kodun tamamı tek bir modülde durmalı. Şimdiden bir protokol veya soyutlama katmanı kurulmayacak.

## Anti-hedefler (çalışsa bile başarısızlık sayılır)

- **API kredisi harcamak.** Tüm Claude çağrıları `claude -p` üzerinden kullanıcının claude.ai aboneliğiyle yapılır. Çağrı yapılırken `ANTHROPIC_API_KEY` ortamdan çıkarılır, çünkü tanımlıysa Claude Code onu tercih eder. `--bare` **kullanılmaz**, çünkü bu kip yalnızca API anahtarıyla çalışıyor.
- **Ham veriyi paylaşmak.** Ham konuşma kaydı, prompt metni, kod içeriği veya secret'lar Supabase'e gitmez. Yalnızca aşağıdaki özet alanlar paylaşılır.
- **Session'ları yavaşlatmak veya bozmak.** Hook'lar milisaniyeler içinde biter, ağa çıkmaz, hiçbir şeyi bloklamaz. Hata alsalar bile session'ı etkilemezler (her durumda exit 0).
- **Eventpal'in canlı Supabase projesine dokunmak.**
- **Kullanıcının mevcut `~/.claude/settings.json` hook'larını veya ayarlarını ezmek.** Kurulum, mevcut ayarlarla birleştirme yaparak çalışır.

## Kısıtlar

- macOS 27, Xcode kurulu, Swift 6.4. Menü çubuğu için SwiftUI `MenuBarExtra` kullanılır.
- Claude Code 2.1.30x, kimlik doğrulama claude.ai Team aboneliğiyle yapılıyor. Anıl'ın da aynı Team organizasyonunda olduğu tahmin ediliyor.
- Claude Code'un iç dosya formatları (transcript, `~/.claude/sessions`) belgelenmemiş ve güncellemelerde değişebilir. Okuyucular toleranslı olmalı: bilinmeyen satır veya alan atlanır, uygulama çökmez, ilgili alan "bilinmiyor" görünür.
- **Supabase ücretsiz planı:**
  - Onur, `oer@eventpal.co` ile ücretsiz bir Supabase hesabı açtı ve GitHub hesabını bağladı (2026-10-23). Proje bu hesabın ücretsiz organizasyonuna açılır.
  - Proje Eventpal'in ücretli organizasyonu altına açılmaz. Ücretli organizasyonda her ek proje ücretlendirilebiliyor.
  - Ücretsiz projeler bir hafta kullanılmazsa uykuya alınır. Bu durumda uygulama "paylaşım kapalı" gösterir ve kişisel kısım çalışmaya devam eder.
- **Dağıtım:** Anıl'a derlenmiş `.app` gönderilir. Apple Developer ID varsa uygulama imzalanır ve notarize edilir. Yoksa Anıl ilk açılışta macOS uyarısını elle geçer, bunun talimatı verilir.

## Veri kaynakları (Onur'un makinesinde doğrulandı)

1. **`claude agents --json`:** Aktif session'ları (interaktif ve arka plan) script'ler için JSON olarak verir.
   - Alanlar: `id`, `pid`, `sessionId`, `name`, `cwd`, `kind` (`interactive` / `background`), `startedAt`, `status` (`idle` / `busy`) ve `state` (`working` / `blocked`, yalnızca arka plan session'larında).
   - `--all` bayrağı tamamlanmış arka plan session'larını da ekler.
   - Session listesinin ana kaynağı budur.
2. **`~/.claude/sessions/<pid>.json`:** Her canlı session için `sessionId`, `name`, `cwd`, `status` (`busy` / `idle`) ve `statusUpdatedAt` alanlarını tutar.
3. **Transcript (`~/.claude/projects/<cwd-slug>/<sessionId>.jsonl`):** Belgelenmemiş bir format. Kullanışlı satır tipleri:
   - `ai-title` (`aiTitle`): Claude'un otomatik ürettiği session başlığı.
   - `last-prompt` (`lastPrompt`): kullanıcının son verdiği görev.
   - `user` ve `assistant` satırları: `message`, `timestamp`, `gitBranch`, `cwd`. Asistan mesajlarındaki `tool_use` blokları son eylemi verir (tool adı ve dosya yolu ya da komut).
4. **Hook'lar:** Belgelenmiş ve en canlı sinyal.
   - Kullanılacak olaylar: `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Notification`, `Stop`, `StopFailure`, `SessionEnd`.
   - `Stop` olayının girdisinde `last_assistant_message` (Claude'un son mesajı) ve `background_tasks` alanları var. `StopFailure` olayında ise `error` alanı var (ör. `rate_limit`).
   - Her hook stdin'den `session_id`, `transcript_path`, `cwd` ve olaya özgü alanları alır.
   - `Notification` olayının `notification_type` alanı şu değerleri alabilir:
     - `permission_prompt`: izin bekleniyor, yaklaşık 6 saniye sonra tetiklenir.
     - `idle_prompt`: Claude cevabını bitirmiş ve kullanıcı 60 saniyedir yazmamış.
     - `elicitation_dialog`
     - `agent_needs_input`
     - `agent_completed`
   - Hook komutu olayı yalnızca yerel, append-only bir olay günlüğüne yazar. Uygulama bu günlüğü izler.
   - "Seni bekliyor" durumu bekleyen bir izin, elicitation veya `agent_needs_input` demektir. Bunun yanında `Stop` sonrasında son asistan mesajı kullanıcıya bir soruyla bitiyorsa da bu durum gösterilir. Bunun ayrıntılı kuralı builder'a bırakıldı.
5. **Session durum dosyası (yeni):** Her session'a kendi durumunu kısa ve yapılandırılmış biçimde yazması söylenir.
   - **Talimat nasıl verilir:** Talimatı `SessionStart` hook'u verir. Claude Code, bu hook'un stdout çıktısını session'ın bağlamına ekliyor. Hook çıktısı, o session'a özel durum dosyasının mutlak yolunu da (`~/.session-radar/status/<session_id>.json`) içerir. Hook her başlangıçta, devam ettirmede, `/clear`'da ve compaction'da çalıştığı için talimat compaction'dan sonra da kaybolmaz. *(Claude'un kararı, 2026-10-23. İlk düşünülen `~/.claude/rules/` kural dosyasının yerini aldı. Kural dosyasında session kendi kimliğini öğrenmek için Bash çalıştırmak zorunda kalıyordu, bu da izin sorusu çıkarabiliyordu.)*
   - **Nasıl yazılır:** Session dosyayı Write tool'uyla yazar. İzin sorusu çıkmaması için kurulum `permissions.allow` listesine `Edit(~/.session-radar/status/**)` ve `Read(~/.session-radar/status/**)` kurallarını ekler. Claude Code, Write tool'u için `Edit` kurallarına bakıyor.
   - İçerik: görev, neden, aşama, sıradaki adım, checklist (`[{text, done}]`), sorunlar ve konu listesi.
   - Konu listesi `[{title, state}]` biçimindedir, eskiden yeniye sıralanır. `state` değeri `active` (tek bir tane olur), `open` ya da `done` olabilir.
   - Session dosyayı güncellemeden önce okur ve eski konuları korur.
   - Session ne zaman güncelleme yapar: görev başında, aşama değişince, iş bitince ve sorun çıkınca.
   - Durum dosyası yoksa yedek değerler kullanılır: başlık `aiTitle`'dan, görev `lastPrompt`'un kısaltmasından gelir ve aşama "bilinmiyor" olarak gösterilir.
6. **Değişen dosyalar (çakışma tespiti için):**
   - Session bazında: `Edit` / `Write` hook olaylarındaki dosya yolları.
   - Repo bazında: session'ın cwd'sindeki `git status --porcelain`.
   - Aynı remote'a sahip worktree'ler aynı repo sayılır.
   - Yollar repo köküne göre göreli tutulur, çünkü iki makinedeki klasör yolları farklı.

## Mimari (karar verilenler)

- **Tek bir Swift menü çubuğu uygulaması.** Yerel kaynakları okuyup her session için bir anlık görüntü üretir. Bu görüntü UI'ı, bildirimleri ve Supabase yayınını besler.
- **Hook komutu:** küçük bir script veya binary. Kurulum sırasında `~/.claude/settings.json` dosyasına birleştirme yoluyla eklenir. Yalnızca olayı yerel günlüğe ekler.
- **Uygulamanın kendi Claude çağrıları filtrelenir.** "Soru sor" özelliğinin yaptığı `claude -p` çağrıları da birer session ve transcript oluşturur, hook'ları da tetikler. Bu çağrılar ayrılmış bir çalışma klasöründen yapılır (ör. `~/.session-radar/ask`) ve o klasöre ait session'lar listede gösterilmez, yayınlanmaz.
- **"Soru sor":**
  - Komut: `env -u ANTHROPIC_API_KEY claude -p --model haiku`
  - Bağlam olarak transcript'in son bölümü ve durum dosyası verilir.
  - Cevap panelde gösterilir.
- **Paylaşım:**
  - Supabase'de session başına bir satır tutulur (upsert) ve değişiklikler Realtime ile dinlenir.
  - Paylaşılan alanlar: `owner`, session id, session adı, repo (normalize edilmiş remote), branch, durum, görev başlığı, aşama, sıradaki adım, ilerleme (yapılan/toplam), kısa sorun metni, değişen dosyalar (repo'ya göre göreli) ve `updated_at`.
  - Görev başlığı ve sıradaki adım, session'ın kendi yazdığı kısa özet metinlerdir.
- **Erişim güvenliği:**
  - Supabase anon anahtarı uygulamanın içinde dağıtılacağı için tek başına koruma sağlamaz.
  - İki kullanıcı Supabase Auth ile giriş yapar ve yeni kayıt kapalı tutulur.
  - RLS kuralları: giriş yapmış kullanıcı tüm satırları okuyabilir, yalnızca kendi `owner` satırlarını yazabilir.
- **Bayat veri:**
  - Session bittiğinde satırı "bitti" olur ya da kaldırılır.
  - Bir süre güncellenmeyen satır soluk gösterilir (heartbeat).
  - Bu sürelerin ayrıntısı builder'a bırakıldı.

## Kullanıcının verdiği kararlar

- Biçim: macOS menü çubuğu uygulaması, canlı.
- Anıl'ın session'ları işin asıl parçası ve aynı listede yer alır.
- API kredisi kullanılmaz, her şey abonelik üzerinden yürür.
- Paylaşım şimdilik Supabase ücretsiz planıyla yapılır. Tailscale daha sonra ek bir seçenek olarak gelir.
- Özetleri session'lar kendileri yazar. Haiku yalnızca kullanıcı soru sorduğunda kullanılır.
- Her session'ın konu akışı görünür: şu anki konu, önceki konular ve bunların açık mı kapalı mı olduğu.
- Proje klasörü: `~/Desktop/Projeler/session-radar`.
- **Aşamalar (2026-10-23):**
  - **Bu aşama:** Yalnızca Onur'un kendi kullanımı. Kapsamda 1–7 numaralı hedefler var: yerel veri, panel, bildirimler, soru sorma ve Onur'un kendi session'ları arasındaki çakışma uyarısı.
  - **Sonraki aşama:** Paylaşım (8. hedef, Supabase) ve Anıl entegrasyonu ayrı bir plan olarak ele alınacak. Anıl'ın kurulumu da o aşamada doğrulanacak: Claude Code sürümü, giriş yöntemi (abonelik mi API anahtarı mı) ve macOS sürümü.
  - Bu aşamada Supabase'e hiçbir şey yazılmaz. Paylaşım kodu, sonraki aşamada tek bir modül olarak eklenebilecek şekilde yer bırakılır.

## Builder'a bırakılanlar

- Görsel tasarım ve panel düzeni.
- "Seni bekliyor" tespitinin ayrıntılı kuralı.
- Olay günlüğünün formatı ve dosya izleme yöntemi.
- Talimat metninin tam ifadesi.
- Supabase şemasının ayrıntıları ve bayat satır temizliği.
- Kurulum akışı (hook ve izin kurallarının birleştirilmesi, oturum açılışında başlatma, Supabase girişi) ve Anıl için kurulum talimatı.
- Test yaklaşımı.
