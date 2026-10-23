# Ertelenen küçük bulgular

Per-task ve son incelemelerde bulunup ertelenen Minor bulgular ve kapsam dışı gözlemler (2026-10-23). Satırlar SDD defterlerinden olduğu gibi alındı.

## MVP planı

- Task 1: minor (deferred): HookRecordTests notebook_path, AskUserQuestion 200 sınırı, Notification 200 sınırı, StopFailure error, Stop 300 son ek, RadarPaths.isInternal/fromEnvironment testleri yok
- Task 1: minor (deferred): Models.swift:220 isInternal standardizedFileURL symlink çözmüyor (/var vs /private/var)
- Task 1: minor (deferred): HookRecord.swift:77 String(first.prefix(120)) daha sade
- Task 2: minor (deferred): EventReducer.swift:149 dosya değişimi yalnızca boyut küçülürse algılanıyor (inode karşılaştırması yok)
- Task 2: minor (deferred): EventReducer.swift:148 7 günü aşan dosyaların offset kayıtları temizlenmiyor
- Task 2: minor (deferred): EventReducer.swift:37 describeAction boş target'ta cwd adını verir
- Task 2: minor (deferred): EventReducerTests kesme, 7 gün sınırı, nil target, quota dalları testsiz
- Task 3: minor (deferred): transcript lastAction Bash komutunu kırpmıyor (çok satırlı/uzun komut) — UI'da lineLimit ya da kırpma gerekir
- Task 3: minor (deferred): SourcesTests kesik satır testi zayıf (yarım satır zaten parse edilemiyor); global `fixture` adı genel
- Task 3: minor (deferred): testsiz: 64KB sınırı, eksik dosya, isMeta, dizi content, findTranscript
- Task 3: minor (deferred): Sources.swift:26 fileSize okunamazsa 64KB koruması atlanıyor
- Task 4: minor (deferred): Git.swift:51 Y sütunundaki R/C kontrol edilmiyor
- Task 4: minor (deferred): Git.swift:79/81 trimming baştaki/sondaki boşlukları da siliyor
- Task 4: minor (deferred): Git.swift:26 kodlanmamış / içeren parola kısmen kalabilir
- Task 4: minor (deferred): GitTests sh yardımcısı çıkış kodunu kontrol etmiyor; testsiz: rename, untracked klasör, origin/HEAD yedeği, detached HEAD
- Task 4: minor (deferred): Git.swift:32 isRunning/terminate sınırda yarış; terminate yalnızca git'i öldürür (alt süreç pipe'ı açık tutarsa okuma bloklanabilir)
- Task 4: minor (deferred): silinmiş dosya testi eski çözücüye karşı kırmızı görülmedi
- Task 5: minor (deferred): Snapshot.swift:43 CRLF split; :49 boş cwd'de lastPathComponent süreç cwd'sini verir; :79 sıralama kararsız (id ile tie-break yok, rank force-unwrap); :37 isAlive pid>0 kontrolü yok
- Task 5: minor (deferred): SnapshotTests: çakışma adı yedeği, startedAt ms, action/progress, shouldKeep, tie-break testsiz
- Task 6: minor (deferred): unmerge kullanıcının zaten boş olan "Stop": [] / "hooks": {} kapsayıcılarını siliyor
- Task 6: minor (deferred): dizi içinde sözlük olmayan girdi varsa bizim hook kalıyor ve merge tekrar ekliyor (bozuk girdi)
- Task 6: minor (deferred): uninstall bizim girdi yokken de dosyayı yeniden biçimlendirip yazıyor
- Task 6: minor (deferred): InstallError LocalizedError değil; symlink settings.json atomik yazımda normal dosyaya dönüşür
- Task 6: minor (deferred): InstallerTests karışık grup, boş kapsayıcı, [] JSON, yedek içeriği, uninstall testsiz
- Task 6: minor (deferred): ilk yedek kalıcı olduğu için eskiyebilir (ruling gereği); uninstall da tuhaf şekilde reddeder
- Task 7: minor (deferred): Claude.swift:59-70 stdin yazıcı, çocuk süreç 64KB'tan büyük prompt'u okumadan çıkarsa sonsuza kadar bloklanabilir (status 64KB + dialog 20k) — final review değerlendirmeli
- Task 7: minor (deferred): Claude.swift:50 terminate yalnızca SIGTERM, SIGKILL'e yükseltme yok
- Task 7: minor (deferred): Claude.swift:83 gürültülü login shell çıktısında command -v sonucu kaçar (son satır alınmalı)
- Task 7: minor (deferred): ClaudeTests timeout yolu ve ANTHROPIC_AUTH_TOKEN silme testsiz
- Task 8: minor (deferred): UNUserNotificationCenterDelegate yok — panel açıkken banner bastırılır (willPresent → .banner,.sound)
- Task 8: minor (deferred): lastError hiç temizlenmiyor ("claude bulunamadı" claude kurulduktan sonra da kalır)
- Task 8: minor (deferred): activities/repos sözlükleri uygulama yeniden başlayana kadar büyüyor
- Task 8: minor (deferred): findTranscript bulunamayan session için her saniye proje klasörünü tarıyor (negatif önbellek yok)
- Task 8: minor (deferred): ilk refreshSlow tick döngüsünü bekletiyor; yeni session'ın repo bilgisi 10 sn gecikebilir
- Task 8: minor (deferred): sessions/conflicts her saniye yeniden atanıyor; build-app.sh pkill/open yarışı; AskBox cevabı satır kapanınca kaybolur
- Final review: minor (deferred): I1 yalnızca görünen durumu değiştiriyor; kesilmiş session SessionEnd'siz kapanırsa yanlış "beklenmedik kapandı" (Task 0 ile büyük ölçüde çözülür)
- Final review: minor (deferred): kayıt dosyasında pid yeniden kullanımı (procStart ile doğrulanabilir); candidate cwd ile snapshot cwd farklı kaynaklardan; -p session'ları 15 sn sessizlikte closed↔working gidip geliyor
- Final review: out-of-scope: izin isteminde Esc/red sonrası "Seni bekliyor" bir sonraki isteğe kadar kalıyor; /clear sonrası kayıt sessionId'sinin güncellendiği elle doğrulanmalı

## Session penceresi planı

- Task 0: minor (deferred): soru testi yeni dalı çalıştırmıyor; idle_prompt note'u temizlemiyor
- Task 1: minor (deferred): History.swift:81 çok bloklu satırda text'ler birleştiriliyor (spec: son blok); :73 iç içe "type":"user" içeren asistan satırı cevabı düşürebilir; :101 her satır kopyalanıyor; :96 çok uzun tek satırda carry'nin tekrar taranması (kuadratik); boş istek sayılıyor
- Task 1: minor (deferred): HistoryTests: parça sınırında çok baytlı karakter, 2000 sınırı, zaman damgası biçimleri, sidechain asistan, topicsDir izinleri, partial line offset testsiz; smoke süre sınırını assert etmiyor
- Task 2: minor (deferred): Topics.swift:127 mergeTopics zaten bir konuda olan ya da tekrarlanan indeksi tekrar ekler; istek metni prompt'a ham giriyor (prompt enjeksiyonu riski, sınırlayıcı/"veri olarak ele al" satırı eklenebilir); id yeniden kullanımı başlığı ezer; .iso8601 kesirli saniyeyi düşürür
- Task 2: minor (deferred): TopicsTests boş başlık, eksik mevcut konu, boş konu atma, sıralama, reply maliyeti, prompt'ta mevcut konular, bozuk dosya testsiz
- Task 3: minor (deferred): boş başlıklı active konu "Konu: " gösterir (Task 2 doğrulaması boş başlığı reddediyor); zamanlayıcı 120 sn sınırı/seçili-uygunsuz yedek testsiz; startContext metni birebir sabitlenmemiş; cand yardımcısı private değil
- Task 5: minor (deferred): TopicCard her body'de filter (Set ile ucuzlatılabilir); konusuz istek listesi lazy değil; tarih biçimleyiciler @MainActor değil; bağlantı çizgisi kartlar arasında kopuk olabilir; repoName nil iken branch gösterilmiyor
- Task 4: minor (deferred): uygulama kapalıyken yeniden yazılan transcript algılanmıyor (ilk görüşte file.grouped > requests.count → truncated sayılabilir); session id konu dosyası yolunda doğrulanmıyor (isValidSessionId public yapılabilir); geçersiz çıktı 120 sn'de bir sonsuza dek yeniden denenir (geri çekilme yok); saveTopicFile hatası sessiz; düşen eski cevap lastRunAt yazmıyor
- Task 4: minor (deferred): yeni birikim davranışı için test yok
- Final review: re-review — tümü addressed, yeni Critical/Important yok. Kalan minor: yeni istek failures'ı sıfırlayınca yeniden 120 sn ritmi; daha yeni sürümlü dosya üzerine yazılır; geç gelen Haiku cevabı reset sonrası yeni işe karışabilir (öncesinden kalma); Engine yolları testsiz; spec'te "Transcript yapısı" satırı eski.

## Ayrı ele alınacak

- ~~Arka plan session'ı 19e2c8ef sürekli "Çalışıyor"~~ — çözüldü (6c733c3): olaysız session'da süreç `status` alanı esas alınıyor.

## Yeni arayüz planı (2026-10-23-native-ui)

Task ve son incelemelerden kalan, birleştirmeyi engellemeyen bulgular:

- Konular: Haiku `from` alanını yazmazsa kayıtlı sapak bilgisi silinir (spec: son geçerli cevap esas).
- Akış: dal yerleşimi açık dallar arasında sırayla yukarı/aşağı dönüşüyor; önceki bir dal kapanınca sonraki açık dallar taraf değiştirir (plan kuralı 4). Kalıcı şerit ataması gerekirse ayrı iş.
- Akış: ana hattaki ara kartın arkasından geçen dal çizgisi yanlış karttan çıkıyormuş gibi görünebilir (kesişme önleme yok).
- Tuval: mini haritadaki görünen alan çerçevesi odak animasyonunda hareket etmek yerine atlıyor; kart yükseklikleri tahmini (çok satırlı kartlarda ortalama ve mini harita hafif kayar); sürükleme sırasında konu değişirse kamera bir kez takip edebilir.
- Tuval: pencere boyutu `body` içinden zamanlanan bir Task ile eşitleniyor (`FlowCanvas.swift:52`, yorumlu). Daha temiz yol: `geo.size`'ı kameranın komut yollarına doğrudan geçirmek.
- Tuval: kırmızı sorun satırlarının beyaz kart üzerindeki kontrastı ~4:1 (sınırda).
- Pencere: adım listesi seçimden sonra 300 ms × 2 kaydırıyor; bu sürede elle kaydırma geri çekilir. Gün aşan konuların istek satırları yalnızca saat gösteriyor.
- Panel: konu şeridi noktaları VoiceOver'da ayrı ayrı seçilemiyor (kart tek öğe). İzin isteğinde ne tool ne mesaj varsa kartta durum dosyasındaki sorun metni görünebilir (nadir).
- Elle doğrulanacaklar: cam görünümü, hover ve tıklamalar, kaydırma/yakınlaştırma, VoiceOver.
