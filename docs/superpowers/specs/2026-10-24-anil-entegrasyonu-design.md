# Session Radar — Anıl entegrasyonu: çakışma önleme

Tarih: 2026-10-24 · Sahibi: Onur · Kullanıcılar: Onur ve Anıl

Bu doküman, `2026-10-23-session-radar-design.md` içindeki şu kısımların yerine geçer:
- 3. hedefteki "kişiye göre gruplama (Onur / Anıl)",
- 7. hedefin Anıl'la ilgili kısmı,
- 8. hedef ("Paylaşım"),
- "Paylaşım" mimari bölümündeki alan listesi.

Onur'un kendi session'ları arasındaki dosya çakışması uyarısı olduğu gibi kalır.

## Amaç ve neden

Onur ve Anıl, OnlyEvent'i taşırken web, mobil ve scraper repolarında paralel çalışıyor. Bu sırada iki sorun yaşanıyor:

- **Aynı işi iki kez yapmak.** İkisi de habersizce aynı konuya giriyor ve farklı yollarla çözüyor.
- **Geç fark edilen push'lar.** Biri push'luyor. Öbürü pull etmeden kendi değişikliğini geliştirmeye devam ediyor ve bunu çok sonra fark ediyor. Merge sırasında "hangimizinkini alalım, hangisi daha doğru" sorusu çıkıyor.

Onur'un sözleriyle istenen şu: Bir projede bir şeyle biri ilgileniyorsa öbürü o an onunla ilgilenmesin. Agent da kendi kullanıcısına "bak, Onur şu anda tam bunu yapıyor, bırakalım o çözsün, biz başka bir şeye bakalım" desin.

Başarı ölçüsü: daha az conflict, daha az tekrarlanan iş, daha az boşa giden token.

## Hedefler

1. **Sahiplik uyarısı.**
   - Ne zaman: Onur'un canlı bir session'ı paylaşılan bir repoda bir konuyla ilgileniyorsa, Anıl'ın aynı repodaki agent'ı bunu bilir.
   - Ne yapar: Anıl'ın istediği iş o konuyla aynıysa ya da çok yakınsa, agent işe girmeden Anıl'a söyler ve devam edip etmeyeceğini sorar.
   - Bu kural ters yönde de aynen işler.
2. **Push haberi.**
   - Ne zaman: Paylaşılan bir repoda, Onur'un canlı bir session'ının çalıştığı branch'e başkası push atar.
   - Bildirim: Onur'a bir macOS bildirimi gelir.
   - Agent: O session'ın agent'ı, bir sonraki dosya düzenlemesine ya da commit'e geçmeden önce pull eder.
   - Çakışma: Pull sırasında çakışma çıkarsa agent hangi tarafın alınacağına kendisi karar vermez, durur ve kullanıcıya sorar.
   - Bu kural Anıl için de aynen işler.

## Hedef dışı

- **Karşı tarafın session'larını gösteren bir ekran.** Panelde, pencerede ya da menü çubuğu simgesinde Anıl'ın session'ları listelenmez. Sistem arka planda çalışır ve yalnızca iki durumda kendini gösterir: agent'ın uyarısı ve push bildirimi.
- **Görev paslama.** Şu an WhatsApp'tan yapılıyor ve eksik bir yanı yok.
- **Kural ve sınır paylaşımı.** Onur'a göre nadir yaşanıyor ve öncelikli değil.
- **Dosya listesi paylaşımı.** Paylaşılan alanlar aşağıdaki listeyle sınırlı.
- **Anıl'ın session'larına soru sormak.**
- **Tailscale.** v1'de yok. Supabase'le konuşan kodun tamamı tek bir dosyada durur. Böylece Supabase daha sonra Tailscale ile doğrudan bağlantıya çevrilebilir. Bunun için şimdiden protokol ya da soyutlama katmanı kurulmaz.
- **Kesin engel.** Sahiplik bir uyarıdır, yasak değildir. Kullanıcı "yine de yapacağım" derse agent devam eder.

## Anti-hedefler (çalışsa bile başarısızlık sayılır)

- **Gözetleniyormuş hissi.** Onur'un sözleri: "sürekli birbirimizi gözlemliyor gibi olmak istemiyorum." Bu yüzden:
  - kalıcı bir geçmiş tutulmaz,
  - "Anıl şu an ne yapıyor" diye bakılacak bir yer yoktur,
  - karşı tarafın agent'ı geri çekildiğinde kimseye bildirim gitmez.
- **Ham verinin dışarı çıkması.** Konuşma kaydı, prompt metni, kod, dosya içeriği ve secret'lar paylaşılmaz.
- **Sessiz merge kararı.** Agent, çakışmada iki taraftan birini kullanıcıya sormadan seçmez.
- **Token israfı.** Aynı not bir session'a tekrar tekrar gönderilmez. Karşı tarafın o repoda canlı bir kaydı yoksa agent'a hiçbir şey gitmez.
- **API kredisi harcamak.** Bu özellik yeni bir Claude ya da Haiku çağrısı eklemez. Benzerliği agent'ın kendisi değerlendirir.
- **Eventpal'in canlı Supabase projesine dokunmak.**

## Davranış

### Paylaşılan repolar (izin listesi) *(Claude'un kararı)*

- Paylaşım yalnızca kullanıcının seçtiği repolarda çalışır, yani Eventpal'in web, mobil ve scraper repolarında.
- Repolar normalize edilmiş remote adresiyle (`normalizeRemote`, örneğin `github.com/org/eventpal-mobile`) eşleşir. İki makinedeki klon yolları farklı olabileceği için yol kullanılmaz.
- Listede olmayan repoda:
  - Supabase'e hiçbir şey yazılmaz,
  - karşı tarafın kayıtları okunmaz,
  - `git fetch` yapılmaz,
  - agent'a ekip notu gitmez.

  Session Radar gibi kişisel projeler bu yüzden tamamen dışarıda kalır.

### Sahiplik kaydı

- **Kim ve ne zaman:** Paylaşılan bir repoda canlı (`alive`) olan bir session için ortak yerde bir kayıt tutulur. Kayıt, o session'daki son kullanıcı isteği **8 saatten yeni** olduğu sürece tutulur (Onur'un kararı).
  - Gerekçe: Onur'un günlerdir açık duran ama dokunmadığı session'ları var. Bunlar, bitmiş bir işin konusunu süresiz sahiplenip yanlış alarm üretmemeli.
  - Son istekten 8 saat geçince kayıt silinir. Yeni bir istek gelirse yeniden yazılır.
- **Kayıttaki alanlar** (yalnızca bunlar):
  - kişinin görünen adı (Ayarlar'da girilir: "Onur", "Anıl"),
  - session id,
  - repo anahtarı,
  - branch,
  - şu anki konu,
  - açık konuların başlıkları,
  - durum: yalnızca "çalışıyor" ya da "boşta",
  - son kullanıcı isteğinin zamanı. Bu alan iki iş görür: agent'a giden notta "son istek 2 saat önce" biçiminde gösterilir ve alan tarafta 8 saat sınırı yeniden uygulanır. Böylece karşı tarafın saati ya da eski bir sürümü sınırı delemez.
  - `updated_at`.
- **"Şu anki konu" nereden gelir:**
  1. Durum dosyasındaki `task` alanı, son kullanıcı isteğinden sonra güncellendiyse. Bu alan session'ın ilk turunda da hazırdır, çünkü konu gruplaması session çalışırken yapılmaz.
  2. Yoksa, Haiku'nun gruplamasındaki `active` konunun başlığı.
  3. İkisi de yoksa kayıt yazılmaz.
- **Açık konular** *(Claude'un kararı; Onur itiraz etmedi)*: Haiku'nun `open` dediği, yani yarım bırakılmış konular da sahiplik sayılır. Bunlar notta "yarım bıraktığı" diye ayrıca belirtilir.
- **Metin sınırı:** Başlıklar tek satırdır ve en fazla 80 karakterdir. Bu sınır gönderilirken de, alınırken de uygulanır.
- **Kaydın düşmesi:**
  - Session kapanınca ya da ölünce kayıt silinir.
  - Son kullanıcı isteğinden 8 saat geçince kayıt silinir.
  - Uygulama kapanırsa ya da makine uykuya geçerse kayıt bayatlar. Belirli bir süreden uzun güncellenmemiş kayıtlar yok sayılır. Bu süre birkaç dakikadır ve değerini uygulayıcı seçer.
  - Konu bitince (`done`) listeden çıkar.
  - Tabloda geçmiş tutulmaz: kayıt başına tek satır vardır ve bu satır güncellenir.

### Agent'a giden ekip notu

- **Hook ağa çıkmaz.**
  - Uygulama, karşı tarafın canlı kayıtlarını ve push haberlerini yerelde, repo başına bir dosyaya yazar.
  - `radar-hook` yalnızca bu dosyayı okur. Hook her tool çağrısında çalıştığı için hızlı kalmalıdır.
- **SessionStart'ta, yalnızca paylaşılan repolarda:** `sessionStartContext`'e kısa bir ekip kuralı eklenir. İçeriği:
  - Bu repo ekip arkadaşıyla ortaktır.
  - Ekip notu karşı tarafın aynı ya da yakın bir konuda çalıştığını söylüyorsa, işe girmeden kullanıcıya söyle ve devam edip etmeyeceğini sor.
  - Push notu gelirse dosya düzenlemeden ve commit'e geçmeden önce `git pull --rebase --autostash` çalıştır.
  - Çakışma çıkarsa `git rebase --abort` ile geri dön, tarafı kendin seçme, dur ve sor.
- **UserPromptSubmit'te**, yalnızca karşı tarafın o repoda canlı bir kaydı varsa: `additionalContext` ile olgu biçiminde bir liste gider. Örnek:
  ```
  Ekip notu (eventpal-mobile): Anıl'ın canlı session'ı var.
  Şu anki konu: "Etkinlik detay tasarımı" (main, çalışıyor, son istek 10 dk önce).
  Yarım bıraktığı: "Takvim filtre hatası".
  ```
- **Tur ortasında:** Karşı tarafın kaydı değiştiyse, örneğin yeni bir konu açıldıysa, değişiklik bir sonraki `PostToolUse` ile bir kez iletilir.
- **Tekrar yok:** Bir session'a aynı içerik ikinci kez gönderilmez. Hook, her session için en son neyi ilettiğini hatırlar.
- **Yazım:** Metin talimat gibi değil, olgu gibi yazılır. Claude Code belgesine göre sistem talimatı kılığındaki metin prompt injection savunmasını tetikler ve agent notu kullanıcıya şüpheli bir şey olarak gösterir. Kural kısmı SessionStart bağlamında durur. Session Radar'ın durum dosyası talimatı da zaten orada çalışıyor.

### Push haberi

- **Kontrol:** Uygulama, paylaşılan repolardaki canlı session'ların klasörlerinde birkaç dakikada bir `git fetch` yapar. Aralığı uygulayıcı seçer *(Claude'un kararı: `fetch`, `ls-remote` değil)*. Böylece yeni commit'lerin yazarı ve değiştirdiği dosyalar görülür; bunun için Supabase gerekmez.
  - `fetch` etkileşimsiz çalışır: `GIT_TERMINAL_PROMPT=0`, ssh'te `BatchMode`.
  - Zaman aşımı vardır.
  - Başarısız olursa sessizce atlanır.
- **Neye bakılır:** Session'ın bulunduğu branch'in upstream'inde, yerelde olmayan commit'lere. Branch'in upstream'i yoksa haber de yoktur.
  - **Yazar filtresi yok** *(Claude'un kararı)*. Yerelde olmayan her commit pull gerektirir, yazarı kim olursa olsun: Anıl, Onur'un başka bir makinesi, GitHub arayüzünden yapılan bir merge ya da bir bot.
  - Bir başka gerekçe: repolarda aynı kişi birden fazla e-postayla görünüyor. Onur'un commit'leri makine adına göre `onur@Mac.hgw.local` ve `onur@Onur-MacBook-Pro-2.local` olarak geçiyor, bu yüzden e-postaya göre süzmek güvenilir değil.
  - **Repolardaki gerçek akış** (2026-10-24'te salt okuma ile bakıldı):
    - `eventpal-mobile`, `onlyevent-scraper-v3` ve `eventpal-image-service`'te son 30 günde merge commit'i yok. İşler doğrudan main'e gidiyor.
    - `onlyeventV2`'de birkaç feature branch ve az sayıda merge var.
    - Bu yüzden aynı branch kuralı asıl durumu yakalıyor. Main'e merge edilen bir feature branch, main'deki session'lara normal bir push gibi yansır.
- **Bildirim:**
  - Her yeni remote ucu için bir kez gönderilir.
  - Metinde commit'lerin yazar adları yer alır. Örnek: "eventpal-mobile main'e 2 yeni commit: Anıl Eren Candan".
  - Gelen commit'lerin dosyaları kullanıcının push'lanmamış dosyalarıyla kesişiyorsa bildirime eklenir. Örnek: "senin değiştirdiğin 3 dosyaya dokunuyor". Bu bilgi `RepoInfo.pending` ile yerelde hesaplanır.
- **Agent:**
  - O repo ve branch'teki her canlı session'a "origin/main'de yerelde olmayan 2 commit var (Anıl, 14:32)" biçiminde bir not gider.
  - Notun, agent'ın bir sonraki `Edit` / `Write` / `NotebookEdit` ya da `git commit` / `git push` çağrısından önce eline ulaşması gerekir.
    - *Claude'un kararı:* Yeni bir push'tan sonraki ilk böyle çağrı `PreToolUse` ile bir kez reddedilir (`permissionDecision: "deny"`) ve gerekçesi not olur. Agent önce pull eder, sonraki çağrılar normal geçer.
    - Bunun nedeni şu: `PreToolUse`'un `additionalContext`'i tool sonucunun yanına düşer, yani o düzenleme yapıldıktan sonra görülür.
- **Pull yöntemi** *(Claude'un kararı)*:
  - Agent `git pull --rebase --autostash` çalıştırır.
  - Bu yöntem repolardaki doğrusal geçmişe uyuyor. Push'lanmamış yerel commit'ler ve commit'lenmemiş dosyalar da bu yolla korunur.
  - macOS git'inde `pull.rebase` ayarı yoksa ayrışmış dalda düz `git pull` hata veriyor. Bu sorun da böylece önlenir.
- **Çakışma:**
  - Rebase ya da autostash çakışırsa agent önce `git rebase --abort` ile eski hâle döner.
  - Sonra durur: hangi dosyalarda kimin commit'iyle çakıştığını kullanıcıya söyler ve nasıl ilerleneceğini sorar.
  - Stash'i elle açmak, WIP commit atmak ya da bir tarafı seçmek kullanıcı onayı olmadan yapılmaz.
- **Haber kapanır:** Remote uç yerel `HEAD`'in atası olduğunda (`git merge-base --is-ancestor`).

### Ayarlar *(Claude'un kararı)*

SwiftUI `Settings` penceresinde şunlar bulunur:
- görünen ad,
- Supabase girişi: e-posta ve parola,
- paylaşım açık/kapalı,
- paylaşılan repoların listesi. Bu liste session'larda görülen repolardan işaretlenerek seçilir, elle remote yazılmaz.

Panelde ve pencerede yalnızca bir şey gösterilir: paylaşım açıksa ve Supabase'e ulaşılamıyorsa küçük bir "paylaşım kapalı" işareti. Karşı tarafa dair hiçbir şey gösterilmez.

## Ortak yer: Supabase

- **Proje:**
  - Onur'un `oer@eventpal.co` hesabındaki ücretsiz organizasyonda yeni bir proje açılır.
  - Eventpal'in canlı projesi ve `eventpal-supabase` MCP araçları kullanılmaz.
  - Proje ayarı ana session tarafından ve Onur'un onayıyla yapılır.
- **Giriş:**
  - Supabase Auth, e-posta ve parolayla çalışır. Yeni kayıt kapalıdır ve iki kullanıcıyı Onur oluşturur.
  - anon anahtarı uygulamanın içinde dağıtıldığı için tek başına koruma sağlamaz.
  - Kullanıcı oturumu Keychain'de tutulur.
- **Tablo ve satır güvenliği:**
  - Tek tablo vardır, satırlar session başına bir tanedir.
  - Her kullanıcı yalnızca `auth.uid()` değeri kendisine ait satırları ekleyebilir, değiştirebilir ve silebilir.
  - Giriş yapmış kullanıcılar tüm satırları okuyabilir. Projede yalnızca iki kişi var.
- **İletişim** *(Claude'un kararı)*:
  - Yeni bağımlılık eklenmez: `URLSession` ve PostgREST REST uçları kullanılır.
  - Realtime yerine yoklama kullanılır. Uyarı zaten bir sonraki istekte okunduğu için birkaç saniyelik gecikme önemli değil.
  - Yoklama aralığını ve kayıt güncelleme aralığını uygulayıcı seçer. Bu aralıklar ücretsiz planın sınırlarının çok altında kalmalıdır.
- **Uyku:**
  - Ücretsiz projeler bir hafta kullanılmazsa uykuya alınır.
  - Bu durumda yalnızca "paylaşım kapalı" işareti görünür. Kişisel kısım, push haberi de dahil, çalışmaya devam eder.

## Güvenlik

- **Gelen başlıklar güvenilmeyen veridir.** Karşı taraftan gelen konu başlıkları Haiku çıktısıdır ve dolaylı olarak dış metinden, örneğin scraper'ın okuduğu sayfalardan, türemiş olabilir. Bu yüzden:
  - tek satıra indirilir, kontrol ve biçim karakterleri atılır, 80 karakterle kesilir (`Topics.swift`'teki `oneLine` kuralı);
  - notta tırnak içinde, veri olarak yer alır;
  - ad alanı için de aynı kural geçerlidir.
- **Hook, karşı taraftan gelen metni hiçbir zaman komut ya da yol olarak kullanmaz.**
- **Ağ ve git:** Supabase'e yalnızca yukarıdaki alanlar gider. `git fetch` yalnızca izin listesindeki repolarda çalışır.
- **Ayar dosyası:** `~/.claude/settings.json` yalnızca kurulum betiğiyle, yedek alınarak ve birleştirme yapılarak değiştirilir. Testler gerçek dosyaya dokunmaz.

## Kısıtlar

- Swift 6.4, SwiftPM, en eski sürüm `.macOS(.v14)`. Liquid Glass yalnızca `#available(macOS 26, *)` içinde kullanılır.
- Tüm Claude çağrıları abonelik üzerinden yapılır. Bu özellik zaten yeni bir çağrı eklemez.
- Hook'un kurulu olay listesi değişmez, çünkü `SessionStart`, `UserPromptSubmit`, `PreToolUse` ve `PostToolUse` zaten kurulu. Hook'un çıktısı JSON `hookSpecificOutput` biçimine geçer. SessionStart'taki mevcut düz metin davranışı korunur.
- Mevcut 122 test geçmeye devam eder. Release derlemesi (`swift build -c release`) hatasız olmalıdır.

## Dağıtım ve Anıl'ın kurulumu

- **Anıl'ın ortamı:** Mac kullanıyor, Claude Code'u abonelikle kullanıyor (Onur doğruladı).
- **Doğrulanacak:**
  - macOS sürümü 14 ya da üstü mü (`sw_vers`),
  - Claude Code sürümü `CLAUDE_PID` ve `hookSpecificOutput.additionalContext` destekliyor mu (`claude --version`).
- **Gönderim:**
  - Apple Developer hesabı gerekmez.
  - Onur'un makinesinde derlenen `.app` zip olarak Anıl'a gönderilir.
  - Anıl'a tek bir kurulum komutu ve ilk açılıştaki macOS uyarısını nasıl geçeceğinin talimatı verilir. Komut karantina işaretini kaldırır, uygulamayı `/Applications`'a koyar ve hook'ları kurar.
  - Kurulum, Onur'daki gibi `settings.json`'u yedekleyerek birleştirir.
- **İlk açılış:** Anıl'ın Session Radar'ı onun kendi session'larını da tam olarak izler. Paylaşım, Ayarlar'da giriş yapılıp repolar seçilene kadar kapalıdır.

## Uygulayıcıya bırakılanlar

- Tablonun sütun adları ve tipleri, bayat kayıt süresi, yoklama ve `fetch` aralıkları.
- Yerel ekip notu dosyasının biçimi ve hook'un "son ilettiğim" bilgisini nerede tuttuğu.
- Ayarlar penceresinin düzeni. Uygulama, mevcut arayüz gibi Apple'ın kendi uygulamalarının çizgisinde olmalıdır.
- Kurulum komutunun biçimi. Bu bir betik olabilir ya da `build-app.sh`'ye eklenen bir seçenek.
