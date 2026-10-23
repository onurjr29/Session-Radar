# Yeni Arayüz: Menü Paneli ve Akış Penceresi — Tasarım

Tarih: 2026-10-23 · Sahibi: Onur · Üst tasarımlar: `2026-10-23-session-radar-design.md`, `2026-10-23-session-window-design.md`

Onaylanan taslaklar (tarayıcıda açılabilir, etkileşimli):
- `mockups/2026-10-23-panel.html`
- `mockups/2026-10-23-window.html`

Taslaklarda örnek veri var. Ölçüler ve renkler yön göstermek içindir; birebir kopyalanacak değerler değildir.

## Amaç ve neden

**Şu anki sorun:** Panel ve pencere alt alta dizilmiş metinlerden oluşuyor. Okuması yorucu, göz neye bakacağını bulamıyor.

**Onur arayüze ne için bakıyor:** Kendi sözleriyle: "Hangi session'ın beni beklediğine ve neye takıldığına bakıyordum."

**Hedef:**
- Panelde bu bilgi ilk iki saniyede görülmeli.
- Pencerede bir session'ın konu akışı Power Automate'teki akışlar gibi görsel bir tuval üzerinde izlenebilmeli.

**Tasarım dili:**
- Apple'ın kendi uygulamalarından biri gibi durmalı. Bir Mac ya da iOS kullanıcısı arayüzde kendini yabancı hissetmemeli.
- Apple'ın şu anki tasarım dili esas alınır: macOS 26 ile gelen ve 27'de de süren Liquid Glass.
- Modern olmalı, ama "yapay zekâ ürünü" gibi görünmemeli.
- Sistemi yormamalı.

## Hedefler

### 1. Menü çubuğu paneli (taslak C)

**Sıralama ve gruplar:**
- En üstte seni bekleyenler, sonra sorunlular, sonra çalışanlar.
- Turu bitmiş ve kapanmış session'lar satır olarak görünmez. En altta yalnızca "✓ n bitti" gibi bir sayı olarak durur.
- Sıralama mevcut `sortForDisplay` ile aynıdır.

**Bekleyen session kartı:**
- Turuncu, hafif renkli bir zemin üzerinde olur.
- Kartta şunlar bulunur:
  - session'ın adı,
  - ne kadar süredir beklediği,
  - senden beklenen soru ya da izin, tırnak içinde ve kendi cümlesiyle,
  - konu şeridi.

**Diğer satırlar:**
- Her satırda bir durum noktası, session adı ve konu şeridi bulunur.
- Sorun varsa tek satırlık bir sorun metni eklenir.
- Sağda "2/5" gibi bir ilerleme sayısı yer alır.
- Görev, neden, aşama ve sıradaki adım gibi uzun metinler panelde gösterilmez; hepsi pencereye taşınır.

**Konu şeridi:**
- Session'ın konuları soldan sağa, eskiden yeniye küçük noktalar olarak dizilir.
- Renkler: yeşil kapandı, turuncu açık kaldı. Şu anki konu session'ın durum renginde ve biraz daha büyük çizilir.
- Şeridin yanında varsayılan olarak şu anki konunun başlığı yazar.
- Bir noktanın üzerine gelince ya da tıklayınca yazı o konunun başlığına ve durumuna dönüşür. Seçili nokta bir halka ile işaretlenir.

### 2. Akış penceresi (taslak B)

**Pencere düzeni:**
- **Solda** session listesi bulunur. Mevcut pencerede olduğu gibi seni bekleyenler en üsttedir.
- **Ortada** noktalı bir tuval vardır, Freeform'daki gibi. Seçili session'ın konuları bu tuvalde soldan sağa akan kartlar olarak durur.
- **Sağda** "Adımlar" listesi bulunur.

**Ana hat ve sapaklar** (Onur'un istediği git-branch davranışı):
- Kartlar soldan sağa, konunun başladığı sıraya göre dizilir. Bu sıra, konudaki ilk isteğin zamanıdır.
- Session bir konu sürerken başka bir konuya saparsa, yeni konu ana hattan yukarı ya da aşağı bir dal olarak ayrılır. Ardışık dallar sırayla bir yukarı, bir aşağı açılır.
- Dalın konusu kapanınca (`done`), dal animasyonla ana hatta geri kayar. Haiku sapağı ana konuya bağladığında da konuyu `done` yapar, dolayısıyla aynı şey olur.
- Session sapaktan ana konuya dönmüş ama sapak bitmemişse (`open`), dal ana hatta dönmez. Ucu açık, turuncu bir çizgi olarak kalır.
- Hâlâ süren sapağın (`active`) ucunda, "devam ediyor" anlamında kesik bir çizgi olur.
- Sapağı olmayan konular ana hattın üzerinde durur.

**Kartlar:**
- Her kartta şunlar bulunur:
  - durum ikonu,
  - başlık,
  - durum etiketi (Kapandı / Açık kaldı / Şu an; kapanmış ya da çökmüş session'da Son konu),
  - istek sayısı.
- Şu anki konunun kartı vurgulanır ve canlı bilgileri de taşır:
  - son eylem,
  - durum dosyasındaki görev ve sıradaki adım,
  - kalan işler (checklist),
  - sorunlar,
  - session seni bekliyorsa beklenen soru.

**Adımlar listesi:**
- Session'ın bütün konuları başladıkları sırayla numaralı olarak listelenir. Sapaklar ↳ ile işaretlenir.
- Bir adıma tıklayınca kamera animasyonla o kartın üzerine kayar ve kartı seçer.
- Seçili satır genişler ve şunları gösterir: konunun durumu, saati, istek sayısı, özeti ve konuya ait istekler (zamanlarıyla).
- Tuvalde bir karta tıklamak da listede aynı satırı seçer.

**Kamera:**
- Gezinme: tuval fareyle sürüklenebilir, trackpad'de iki parmakla kaydırılabilir.
- Yakınlaştırma: trackpad'de sıkıştırarak ya da ⌘ ile tekerleği çevirerek yapılır. Sınırlar %40 ile %200 arasıdır.
- **Kaydırma sınırı** (Onur'un isteği): Tuval sonsuza kadar kaydırılamaz. Akışın kapladığı alan, kenarlarına yarım ekranlık pay eklenerek sınır olarak kullanılır. Bu payın tam değeri builder'a kalır.
- "Şu ana dön" düğmesi kamerayı şu anki konuya getirir. Yakınlaştırma yüzdesine tıklamak bütün akışı ekrana sığdırır.
- Pencere açılınca kamera şu anki konuyla başlar.
- **Mini harita** (Onur'un isteği): Tuvalin bir köşesinde bütün akışın küçük bir görünümü durur. Ekranda görünen bölge, mini haritada bir çerçeveyle gösterilir. Mini haritaya tıklayınca ya da çerçeveyi sürükleyince kamera o noktaya gider.

**Soru sorma:** Mevcut "Soru sor" özelliği pencerede kalır.

### 3. Sapak bilgisinin kaynağı

Hangi konunun hangisinden sapılarak açıldığına Haiku karar verir. Bir konuyu yarıda bırakıp başka bir şeye geçmek anlamla ilgili bir karar olduğu için kuralla çıkarılmaz.
- Gruplama cevabındaki her konuya isteğe bağlı bir `from` alanı eklenir. Değeri, bu konunun hangi konunun ortasında ondan sapılarak açıldığını gösteren konu id'sidir. Konu önceki iş bittikten sonra ya da ana iş olarak başladıysa değer `null` olur.
- Haiku zaten her çağrıda konu listesinin tamamını döndürüyor. Mevcut session'larda `from` bilgisi bir sonraki gruplamada dolar. Bunun için ek bir çağrı yapılmaz ve konu dosyasının `version` değeri artmaz.
- `from` bilgisi olmayan eski dosyalarda bütün konular ana hatta görünür.

## Kapsam dışı

- Kartları elle taşımak, konuları düzenlemek, birleştirmek ya da silmek. Yalnızca kamera hareket eder.
- Pencerede eski düz liste görünümüne geçiş düğmesi. İlk taslakta vardı; son taslakta adımlar listesi bu işi gördüğü için kaldırıldı.
- Anıl ile paylaşım (sonraki aşama).
- Tema ya da renk ayarları.

## Anti-hedefler

- **"Yapay zekâ ürünü" görünümü:**
  - mor-pembe geçişler,
  - parlayan kenarlar,
  - ✨ benzeri ikonlar,
  - emojiler,
  - aşırı yuvarlak "oyuncak" bileşenler.
- **Apple'a yabancı kontroller.** Bunlar yerine sistemin hazır bileşenleri kullanılır: sidebar, toolbar, düğmeler, liste satırları, SF Symbols, sistem renkleri ve yazı tipi.
- **Sistemi yormak:**
  - Boştayken hiçbir animasyon ya da kare kare yeniden çizim olmamalı. Animasyonlar yalnızca veri değişince ya da kullanıcı etkileşiminde çalışır.
  - Noktalı zemin yalnızca görünen alan için çizilir.
  - Mevcut 1 saniyelik veri yenilemesi, değişmeyen kartları yeniden çizdirmemeli.
- **Okunabilirliği bozmak.** Açık ve koyu temanın ikisinde de metin kontrastı yeterli olmalı.
- **Para harcamak.** Haiku çağrıları mevcut abonelik yolundan yapılmaya devam eder. Yeni bir çağrı türü eklenmez.

## Kısıtlar

- Üst tasarımların kısıtları geçerlidir:
  - Swift 6 ve SwiftPM,
  - üçüncü taraf bağımlılık yok,
  - `RadarCore` yalnızca Foundation kullanır,
  - arayüz metinleri Türkçe.
- Arayüzden bağımsız mantık `RadarCore`'da yazılır ve test edilir. Bu mantık şunları kapsar:
  - dal ve hat yerleşimi,
  - kaydırma sınırının hesabı,
  - `from` alanının doğrulanması.
- Onur macOS 27 kullanıyor. Anıl'ın macOS sürümü henüz bilinmiyor.

## Onur'un verdiği kararlar

- Panel için taslak C seçildi: bekleyen önde, her satırda konu şeridi. Şeritteki bir noktaya tıklayınca o konunun başlığı yanında görünür.
- Pencere için taslak B seçildi: soldan sağa akış.
- Arayüz Apple'ın tasarım çizgisinde olacak, son tasarım diline göre.
- Sapak dallanması git'teki branch'ler gibi çalışacak: yukarı ya da aşağı açılan bir dal, kapanınca ya da ana konuya bağlanınca ana hatta geri kayar.
- Session'ın bütün adımları bir yanda listelenecek. Tıklayınca kamera o adımın üzerine gidecek.
- Tuval sürüklenebilir olacak.
- Bir mini harita olacak.
- Kaydırmaya bir sınır konacak, kamera akıştan çok uzaklaşamayacak.
- Taslaklardaki tarif "her şey çok doğru" diye onaylandı (2026-10-23).

## Claude'un kararları

- **macOS sürüm desteği:**
  - Liquid Glass yalnızca macOS 26 ve üstünde kullanılır (`glassEffect`, `.buttonStyle(.glass)`).
  - Desteklenen en eski sürüm macOS 14 olarak kalır. Daha eski sürümlerde aynı yüzeylerde standart malzemeler (`.regularMaterial`) kullanılır.
  - Böylece Anıl'ın macOS sürümü ne olursa olsun uygulama çalışır.
  - Sistemin hazır bileşenleri, macOS 26 SDK ile derlendiğinde camı zaten kendiliğinden alır.
- **Adımlar listesinin yeri:** Session listesi solda olduğu için adımlar listesi sağda durur. Seçili adımın ayrıntıları da ayrı bir panel açılmadan bu listede, satır genişleyerek gösterilir.
- **Kamera yeni konuyu takip eder:** Yeni bir konu eklenince kamera ona kayar. Kullanıcı kamerayı elle oynattıysa "Şu ana dön"e basana kadar yerinde kalır.
- **Konu şeridinde konu sayısı:** 8'i geçerse şerit son 8 konuyu gösterir ve başına "+n" koyar. Konunun özeti panelde değil, pencerede gösterilir.
- **Panelde satıra tıklamak:** Pencereyi o session seçili olarak açar.
- **"✓ n bitti" sayısı:** Turu bitmiş ve kapanmış session'ları birlikte sayar. Tıklayınca bunların listesi panelde açılır.
- **Çakışma uyarıları:** Panelde sorun kartlarıyla aynı biçimde, bekleyenlerin altında gösterilir.
- **"Çık" düğmesi:** Panelin başlığındaki küçük bir menüye taşınır.
- **Başlangıç noktası:** Ana hattın en solunda, session'ın başlangıç zamanını gösteren küçük bir kapsül durur. Üzerine gelince ilk istek görünür.
- **Renkler:**
  - Onaylanan taslaklardaki renkler esas alınır; renk değerleri sistem renklerinden gelir.
  - Session durumları: çalışıyor mavi, seni bekliyor turuncu, sorun kırmızı, tur bitti yeşil, kapandı gri. Mevcut uygulamada çalışıyor yeşil, tur bitti maviydi; bu ikisi yer değiştirir.
  - Konu durumları: kapandı yeşil, açık kaldı turuncu. Şu anki konu session'ın durum rengini alır.
- **Sapak bilgisinin doğrulanması:** `from`, var olan başka bir konuyu göstermiyorsa ya da kendisinden sonra başlayan bir konuyu gösteriyorsa yok sayılır.
- **`from` bilgisinin kalıcılığı:**
  - Mevcut `from` değerleri prompt'ta Haiku'ya geri verilir.
  - Haiku'dan, başlıklarda olduğu gibi, bu değerleri gerekmedikçe değiştirmemesi istenir.
  - Haiku'nun son geçerli cevabı esas alınır.
- **Kartlar salt okunurdur:**
  - Pencere taslağındaki "Kapat" düğmesi yalnızca dalın ana hatta geri kayışını göstermek içindi; uygulamada yer almaz.
  - Konu durumlarını yalnızca Haiku belirler.
- **Bekleyen kartın metni:**
  - İzin isteklerinde Claude Code'un bildirim metni genel bir İngilizce cümle olduğu için kartta bekleyen tool ve hedefi gösterilir (ör. "Bash · npm run migrate").
  - Soru sorulduysa sorunun kendisi gösterilir.
- **"Ne kadar süredir bekliyor":** Bu süre beklemenin başladığı andan hesaplanır, son olaydan değil. Çünkü `idle_prompt` gibi sonraki olaylar son olay zamanını ileri taşıyor.
- **Henüz konusu olmayan session:** Tuvalde son isteği gösteren tek bir kart görünür.
- **Sığmayan akış:** Bütün akışı ekrana sığdırmak %40'ın altına inmeyi gerektiriyorsa yakınlaştırma %40'ta kalır.

## Builder'a bırakılanlar

- Tuvalin SwiftUI'daki yapısı. Örneğin dokunma hareketleri, `Canvas` ya da kartlar için ayrı görünümler.
- Kartların ölçüleri ve aralıkları.
- Dal yerleşiminin ayrıntıları: aynı tarafta birden fazla açık dal varsa kaçıncı şeride ineceği, kesişmeleri önleme yöntemi.
- Mini haritanın boyutu ve hangi köşede duracağı.
- Animasyon süreleri ve eğrileri.
- `from` alanının prompt'taki tam metni. Mevcut `<veri>` koruması bozulmamalı.
- Test yaklaşımı.
