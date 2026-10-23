# Session Penceresi ve Konu Geçmişi — Tasarım

Tarih: 2026-10-23 · Sahibi: Onur · Üst tasarım: `2026-10-23-session-radar-design.md`

## Amaç ve neden

Menü çubuğu paneli hızlı erişim için yeterli. Ama Onur bir session'ın gidişatını takip edemiyor:
- session ne için başladı,
- hangi konulardan geçti,
- hangi konular kapandı, hangileri açık kaldı,
- şu an hangi konu üzerinde çalışılıyor.

Session'lar ilerledikçe konu değiştiriyor. Onur bu bilgilerin, session kapanana kadar, unutmamak için görebileceği bir yerde sürekli durmasını istiyor.

**Mevcut durumun eksikleri (2026-10-23'te gözlendi):**
- Konu listesini session'ların kendisi yazacaktı. Ama talimat yalnızca kurulumdan sonra açılan session'lara gidiyor ve hiçbir session henüz durum dosyası yazmadı. `~/.session-radar/status/` boş.
- Konu akışı küçük paneldeki satır detayına sıkışmış durumda. Ayrı bir pencere yok.

## Hedefler

1. **Session penceresi:** Menü panelindeki "Tüm session'lar" düğmesiyle açılan normal bir macOS penceresi.
   - **Solda** session listesi bulunur. Durum renkleri paneldekiyle aynıdır, sıralama da `sortForDisplay` ile aynıdır (seni bekleyenler üstte). Her satırda ad, şu anki konu ve durum görünür.
   - **Sağda** seçili session'ın hikâyesi yukarıdan aşağıya sıralanır:
     - **Başlangıç:** session'ın ilk isteği ve zamanı.
     - **Konu akışı:** dikey bir zaman çizgisi üzerinde, eskiden yeniye konu kartları. Her kartta başlık, durum (şu anki / açık kaldı / kapandı), zaman aralığı ve "ne yapıldı" özeti (en fazla 3 cümle) bulunur. Karta tıklanınca o konuya ait istekler zamanlarıyla birlikte açılır.
     - **Şu an:** şu anki konu vurgulanır. Altında son eylem, durum dosyasından gelen görev, sıradaki adım, kalan işler (checklist) ve sorunlar yer alır.
     - Mevcut "Soru sor" kutusu.
   - Pencere canlıdır: durum ve konular değiştikçe güncellenir.
2. **Otomatik konu gruplama:**
   - Session'ın konuşma kaydındaki kullanıcı istekleri Haiku tarafından konu başlıkları altında gruplanır.
   - Haiku, aboneliğin üzerinden mevcut `runAsk` yoluyla çağrılır.
   - Haiku her konuya bir durum da verir (`active`, `open` ya da `done`).
3. **Kalıcılık:**
   - Konu geçmişi diskte saklanır, bu yüzden uygulama yeniden başlasa da kaybolmaz.
   - Session listede kaldığı sürece görünür. Mevcut kuralla bu, session kapandıktan sonra 24 saate kadar demek.
   - Diskten 7 gün sonra mevcut temizlikle silinir.
4. **Eski session'lar:** Kurulumdan önce açılmış session'ların konuşma kayıtları da gruplanır.
5. **Menü paneli:** Satırdaki "Konu: …" ve "· n açık konu" bilgisi artık bu otomatik konu listesinden gelir.

## Kapsam dışı

- Konuları elle düzenlemek, birleştirmek ya da silmek.
- Session'lar arası konu birleştirme.
- Anıl ile paylaşım (sonraki aşama). Konu listesi ileride paylaşılabilir; bu yüzden ham konuşma değil, özet biçiminde tutulur.
- Session'lara uygulamadan mesaj göndermek.

## Anti-hedefler

- **API kredisi harcamak.** Tüm Haiku çağrıları mevcut `runAsk` komutuyla yapılır (`env -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN … -p --model haiku --tools "" --no-session-persistence --setting-sources project`).
- **Abonelik kotasını hızla tüketmek.**
  - Aynı anda en fazla bir gruplama çağrısı çalışır (global seri kuyruk).
  - Bir session için iki gruplama arasında en az 2 dakika geçer.
  - Gruplama yalnızca yeni istek varsa çalışır.
  - Her çağrıya yalnızca yeni istekler ve mevcut konu listesi gider.
- **Arayüzü bloklamak.** Konuşma kaydı okuma ve Haiku çağrıları ana thread'de yapılmaz.
- **Hatalı model çıktısıyla geçmişi bozmak.** Haiku'nun cevabı geçerli JSON değilse ya da beklenen şemaya uymuyorsa mevcut konu listesi aynen korunur ve sonraki bir fırsatta yeniden denenir.
  - Üst üste başarısızlıklarda bekleme süresi her seferinde iki katına çıkar (120 sn × 2ⁿ, en fazla 1 saat). Başarı ya da yeni istek gelmesi sayacı sıfırlar.
  - 3 başarısızlıktan sonra pencerede bunu belirten tek satırlık bir uyarı görünür. *(2026-10-23 düzeltmesi.)*
- **Konu dosyası sürümü:** Konu dosyaları `version` alanı taşır. Sürümü eşleşmeyen dosya yok sayılır ve session baştan gruplanır, çünkü istek numaralandırması değişirse eski dosyalar yanlış isteklere işaret eder.

## Kısıtlar

- Üst tasarımın kısıtları geçerli: Swift 6, üçüncü taraf bağımlılık yok, `RadarCore` yalnızca Foundation kullanır, UI metinleri Türkçe.
- Konuşma kayıtları çok büyük olabilir (birkaç MB). Okuma artımlı yapılır: her transcript için bir byte offset tutulur ve yalnızca yeni satırlar ayrıştırılır.
- **Transcript yapısı (doğrulandı):** Her içerik bloğu ayrı bir satırdır.
  - Kullanıcı isteği: `type == "user"` olan ve `isMeta` alanı `true` olmayan satır. `message.content` ya string olur, ya da görselli isteklerde `text` ve `image` bloklarından oluşan bir dizi (ayrıntı için "İstek sayılan satırlar" bölümüne bakınız). Satırda `timestamp` alanı da var.
  - Claude'un cevap metni: `type == "assistant"` olan satırlardaki `text` blokları.

## Tasarım kararları (Claude'un kararı, Onur onayladı)

- **Tek konu kaynağı Haiku.** `SessionStart` talimatından `topics` bölümü çıkarılır. Session'lar yalnızca görev, neden, aşama, sıradaki adım, kalan işler ve sorunlar bilgisini yazmaya devam eder. Eski durum dosyalarındaki `topics` alanı okunurken yok sayılır.
- **Ne zaman çalışır:**
  - Gruplamanın tetikleyicisi, session'ın turunun bitmesi ("tur bitti" ya da "seni bekliyor" durumuna geçmesi) ve son gruplamadan bu yana yeni istek olmasıdır.
  - Pencere, gruplanmamış istekleri olan bir session'ı gösterirken de çalışır.
  - Her iki durumda 2 dakikalık bekleme ve global seri kuyruk kuralları geçerlidir.
- **Haiku'ya ne gider:**
  - mevcut konu listesi (JSON),
  - henüz gruplanmamış istekler: her biri numarası ve zamanıyla, en fazla 500 karakter,
  - her isteğin turunda Claude'un son cevap metni: en fazla 300 karakter.

  Tek çağrıda en fazla yaklaşık 30.000 karakter gönderilir. Daha fazlası varsa en eskiden başlanarak parçalar hâlinde, birden fazla çağrıyla işlenir.
- **Haiku'dan ne beklenir:** Yalnızca güncellenmiş tam konu listesi, JSON olarak:

  ```json
  [{"title": "...", "state": "active|open|done", "summary": "...", "requests": [1, 2, 5]}]
  ```

  - En fazla bir `active` konu olur ve bu, en son isteğin ait olduğu konudur.
  - Her istek tam olarak bir konuya aittir.
  - Başlıklar ve özetler Türkçedir.
- **İstek sayılan satırlar** *(Claude'un kararı, gerçek transcript'lerde doğrulandı)*:
  - Yalnızca `type == "user"` olan satırlar. `message.content` ya string olmalı, ya da `tool_result` bloğu içermeyen ve en az bir `text` bloğu olan bir dizi. Bu ikinci biçim ekran görüntüsü eklenmiş istekler için geçerli: `text` blokları birleştirilir, `image` blokları yok sayılır. *(2026-10-23 düzeltmesi: ilk örneklem yalnızca string satırlara bakmıştı. Görselli istekler gerçek isteklerin yaklaşık %18'iydi ve kayboluyordu.)*
  - Tek kelimelik slash komutları istek sayılmaz (ör. `/compact`, `/usage`).
  - Hariç tutulanlar: `isMeta`, `isCompactSummary`, `isVisibleInTranscriptOnly` ya da `isSidechain` alanı `true` olan satırlar; içeriği `<` ile başlayanlar; içeriği `[Request interrupted` ile başlayanlar.
  - `<` ile başlayan satırlar şunlardır: `<task-notification>`, `<command-name>`, `<local-command-stdout>`, `<bash-input>`/`<bash-stdout>` gibi komut ve sistem satırları. Tek istisna `<pasted_content` ile başlayan satırlar, onlar istek sayılır.
  - Son 15 transcript'te string içerikli 252 kullanıcı satırından yalnızca 138'i gerçek istekti. Gerisi bu gürültüydü.
- **Eski session'ları doldurma** *(Claude'un kararı)*:
  - Uygulama açıldığında, kapanmamış (listede canlı) tüm session'ların gruplanmamış istekleri arka planda gruplanır. Böylece menü panelindeki "Konu: …" bilgisi pencere açılmadan da dolar.
  - Kapanmış session'lar yalnızca pencerede seçilirse gruplanır.
  - Global seri kuyrukta pencerede seçili session önceliklidir.
  - 2 dakikalık bekleme yalnızca yeni turların tetiklediği gruplamalar için geçerlidir. Bir session'ın birikmiş isteklerinin parçaları arka arkaya işlenir, kuyruk zaten tek tek ilerlediği için kotayı aynı anda yormaz.
  - Henüz konusu olmayan session'larda panel ve pencere, şu anki konu olarak `lastPrompt` değerini gösterir.
- **Transcript beklenmedik şekilde küçülürse** *(Claude'un kararı)*: Dosya boyutu saklanan offset'ten küçükse o session'ın konu listesi silinir ve baştan gruplanır.
- **Kapanmış session'larda durum** *(Claude'un kararı)*:
  - Session "kapandı" durumundaysa `active` konu "Son konu" olarak etiketlenir, "şu anki" denmez.
  - "n açık konu" sayısı yalnızca `open` konuları sayar, `active` olanı saymaz.
- **Saklama:**
  - Dosya: `~/.session-radar/topics/<sessionId>.json`.
  - İçerik: `sessionId`, gruplanmış istek sayısı, konu listesi ve `updatedAt`.
  - İstek metinleri ve zamanları yeniden üretilebildiği için ayrıca saklanmaz, transcript'ten okunur.

## Kullanıcının verdiği kararlar

- Konular, birbirine bağlı istekler bir başlık altında gruplanacak şekilde gösterilir. Gruplamayı Haiku yapar.
- Ayrı bir pencere olacak. Menü paneli hızlı erişim olarak kalır.
- Geçmiş, session kapanana kadar görünür kalır.
- Yukarıdaki tarif onaylandı (2026-10-23).

## Builder'a bırakılanlar

- Pencerenin görsel tasarımı (SwiftUI `Window` ve `NavigationSplitView` önerilir) ve kart düzeni.
- Prompt'un tam metni, tek koşulla: yalnızca JSON istemeli ve şemayı açıkça vermeli.
- JSON doğrulama ayrıntıları (ör. her isteğin bir konuya ait olması, en fazla bir `active`) ve doğrulama başarısız olursa nasıl davranılacağı.
- Artımlı transcript okuma ve offset saklama ayrıntıları.
- Test yaklaşımı.
