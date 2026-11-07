# flop-miner-tool

FLOP devnet GPU miner'ı kurmak, taşımak ve ayakta tutmak için tek dosyalık bir araç.

Elle kurulum 17 adım ve ~43 komut. Bu araçla sunucuya girdikten sonra **3 komut**.

Hazırlayan: [@KriptoliaTR](https://x.com/KriptoliaTR) · [English](README-EN.md)

> **Doğrulama damgası:** 7 Kasım 2026 · worker `0.1.238` · CLI `v0.1.290` · devnet runtime `1014014`
> Her mod gerçek bir Vast.ai makinesinde (RTX 5060 Ti 16 GB) uçtan uca çalıştırıldı.
> FLOP hızlı değişiyor; bu tarihten çok sonra okuyorsanız önce
> [resmî dokümanlara](https://docs.flop.network/docs/run-miner) bakın.

---
## Ne yapar

| Mod | Ne işe yarar |
|---|---|
| `check` | **Makine kiralamadan önce** çalıştırın. GPU, sürücü, boş VRAM, Docker, disk ve sponsor servisini kontrol eder. |
| `install` | Sıfırdan tam kurulum. Sponsor kuyruğu doluysa **durmaz**; arka plana alır, kalanı bitirir. |
| `restore` | Makineniz öldüyse: aynı 24 kelimeyle yeni makineye taşır. Sponsor adımını **atlar**. |
| `watch` | Tünel adresi değişirse veya worker ölürse yakalayıp düzeltir. |
| `status` | Miner hangi aşamada, iş alıyor mu, nöbetçi çalışıyor mu. |

---

## Kiralamadan önce: bilmeniz gereken üç şey

**1. Devnet ödül vermez.** Token'lar değersiz, zincir sıfırlanabilir, airdrop ağırlığı
taşıdığına dair resmî bir açıklama yok. Buraya öğrenmek ve testnet'e hazır olmak için girilir.

**2. Sponsor kuyruğu var ve süresi öngörülemez.** FLOP yeni miner'ların stake'ini kendi
yatırıyor ama aynı anda sınırlı sayıda kalibre olmamış miner kabul ediyor. Bizim ölçümümüz:

| Deneme | Bekleme |
|---|---|
| 6 Kasım 19:33Z → 7 Kasım 15:06Z | **19 saat 33 dakika** |
| 7 Kasım 16:27Z → 16:28Z | **90 saniye** |

Aynı işlem, bir gün arayla. Kuyruk dönüyor ama ne zaman açılacağı belli olmuyor.
Bu yüzden `install` sponsor adımını **engel olmaktan çıkarıyor**: kurulumun tamamı biter,
arka plan döngüsü ~90 saniyede bir dener, siz bilgisayarınızı kapatıp gidebilirsiniz.
Slot açılınca kayıt geçer ve kalibrasyon ~12 dakikada kendiliğinden tamamlanır.

Sınırla ilgili iki farklı rakam dolaşıyor (aynı anda 40 kalibre olmamış miner; günde 10 veya
100 yeni miner). Hangisinin doğru olduğunu bilmiyoruz, ikisini de FLOP'un resmî bir yerinde
yazılı bulamadık.

**3. Donanım şartı kart modeli değil, iki sayı:**

- **VRAM ≥ 16 GB**
- **Max CUDA ≥ 13.0** (sürücü 580+)

[Vast.ai](https://cloud.vast.ai/?ref_id=849817)'de 16 GB'ı geçen kartların çoğu eski
sürücüde takılı. Kart adına değil, ilandaki **Max CUDA** değerine bakın. Ayrıca
**VM** etiketli şablon seçin; konteyner şablonlarında Docker çalışmıyor.

Filtre ayarları: **Any GPU**, **GPU RAM min 16 GB**, **Disk 60 GB**, On-Demand,
Ubuntu 22.04 VM şablonu. "Open Ports" filtresine gerek yok, tünel kullanıyoruz.
Biz 0.17 $/saat'e RTX 5060 Ti 16 GB kiraladık.

---

## Windows kullanıyorsanız

**WSL kurmanıza gerek yok.** Script sunucuda çalışıyor; sizin bilgisayarınız sadece SSH için
gerekli ve Windows 10/11'de `ssh`, `scp`, `ssh-keygen` yerleşik geliyor. PowerShell açın:

| | macOS / Linux | Windows (PowerShell) |
|---|---|---|
| Anahtar üret | `ssh-keygen -t ed25519` | aynı |
| Anahtarı göster | `cat ~/.ssh/id_ed25519.pub` | `type $env:USERPROFILE\.ssh\id_ed25519.pub` |
| Dosya kopyala | `scp -P <PORT> ...` | aynı |
| Bağlan | `ssh -p <PORT> root@<IP>` | aynı |

---

## Makine kiralama ve bağlanma

Hiç sunucu kiralamadıysanız bu bölüm sizi SSH satırına kadar getirir. Daha ayrıntılı,
ekran görüntülü anlatım için [Ufuk'un rehberi](https://github.com/UfukNode/flop-miner-setup)
bu işin referans metni.

**1. SSH anahtarı üretin** (kendi bilgisayarınızda, bir kez):

```bash
ssh-keygen -t ed25519
```

Dosya adı sorulduğunda **hiçbir şey yazmayın, sadece Enter'a basın.** En sık yapılan hata
buraya komut veya yol yazmak. Parola sorusunu da boş geçebilirsiniz.

Açık anahtarı ekrana basın:

```bash
cat ~/.ssh/id_ed25519.pub
```

`ssh-ed25519 ...` ile başlayan satırın tamamını kopyalayın. Bu satır gizli değildir.
Yanındaki **uzantısız** `id_ed25519` dosyasını ise kimseyle paylaşmayın.

**2. Vast.ai hesabı açın** ve bakiye yükleyin:
[cloud.vast.ai](https://cloud.vast.ai/?ref_id=849817)

Sol menüden **Keys** → **SSH Keys** → **+ New** → kopyaladığınız satırı yapıştırın.
Anahtar, bundan sonra kiraladığınız her sunucuya otomatik eklenir; önce kiralayıp sonra
eklerseniz o sunucuya işlemez.

Bakiye için: test kurulumu ~0.17 $/saat ve ~30 dakika sürüyor. Ama sponsor kuyruğuna
takılırsanız makineyi açık bırakmanız gerekir (yukarıdaki 2. maddeye bakın), o yüzden
**en az 5 $** yükleyin.

**3. Makineyi kiralayın.** Sol menüden **Search**:

- **Change Template** → sağ üstten **VM** etiketi → **Ubuntu 22.04 VM**
- Filtreler: **On-Demand**, **Any GPU**, **GPU RAM min 16 GB**, **Disk 60 GB**
- İlanda **Max CUDA** değerinin **13.0 veya üstü** olduğunu doğrulayın
- Uygun bir makinede **Rent**

**4. Bağlanın.** Sol menüden **Instances**, makine hazır olunca **>_Connect** butonundan
SSH komutunu kopyalayıp kendi terminalinize yapıştırın:

```bash
ssh -p <PORT> root@<IP>
```

Sondaki `-L 8080:localhost:8080` kısmına gerek yok, silebilirsiniz. İlk bağlantıda
sorulan `Are you sure you want to continue connecting?` sorusuna `yes` yazın.

Buradan sonrası sunucuda çalışıyor.

---

## Kullanım

Sunucuya SSH ile bağlandıktan sonra:

```bash
curl -fsSLO https://raw.githubusercontent.com/kriptolia/flop-miner-tool/main/flop-miner.sh
sha256sum flop-miner.sh
bash flop-miner.sh check
```

Hash'i aşağıdaki ile karşılaştırın:

```
0f2fe33f4d8678a89596b1fe9a5d99bd7cbdc59e7cca7c4ee8b31f57827e9ea1
```

Uygunsa kurun:

```bash
bash flop-miner.sh install
```

> `curl | bash` bilerek kullanılmıyor. Kripto tarafında "gördüğün script'i okumadan
> çalıştır" alışkanlığını yaymak, aynı kitleye seed phrase disiplini anlatmakla çelişir.
> Üç satır sürüyor ve doğru refleksi öğretiyor.

Kurulum ~25-30 dakika. Ortada bir kez 24 kelimeniz ekrana gelir ve `evet` yazmanız istenir.
**O kelimeleri kâğıda yazın.** Hiçbir sohbete, mesaja, nota veya yapay zekâya yapıştırmayın.

Kurulum uzun sürdüğü için `screen` içinde çalıştırın; SSH koparsa kurulum devam eder:

```bash
apt-get install -y screen && screen -S flop
```

---

## Makineniz ölürse: `restore`

Devnet'te bu herkesin başına geliyor - bakiye bitiyor, host düşüyor, instance siliniyor.
**Hesabınız zincirde kalıyor.** Yeni makinede:

```bash
# 24 kelimenizi yerine koyun (yedek dosyanız varsa kendi bilgisayarınızdan):
scp -P <PORT> ~/flop-signer-yedek.txt root@<IP>:/opt/flop-miner/signer

# sonra sunucuda:
bash flop-miner.sh restore
```

Test ettik, korunanlar:

| | Korunuyor mu? |
|---|---|
| Hesap / adres | ✅ |
| Sponsorluk (1M stake) | ✅ tekrar istemeye gerek yok |
| **Kalibrasyon** | ✅ **sıfırdan kalibre olmuyorsunuz** |
| Strike kaydı | ✅ |

Restore edilen miner kalibrasyon aşamasını atlayıp doğrudan oturum sunmaya başlıyor.
Sponsor adımı bilerek atlanıyor: **her hesap yalnızca bir kez sponsorlanıyor**, tekrar
denemek kuyruğu boşuna meşgul eder.

> **Yedeğinizi iki dosyadan alın:** `signer` (24 kelime) **ve**
> `session-keys/enclave.seed`. Çoğu kişi sadece kelimeleri yedekliyor; `enclave.seed`
> kaybolursa oturum anahtarı yenileniyor.

---

## Sessiz ölüm: `watch`

Ücretsiz Cloudflare tüneli her yeniden başladığında **yeni adres alıyor.** Adres değişince
miner ağa ölü bir adres duyurmuş oluyor: hiçbir hata mesajı çıkmaz, konteynerler ayakta
görünür, ama iş gelmez. Ve 600 blok içinde cevaplanmayan iş stake'ten kesilir.

```bash
bash flop-miner.sh watch
```

İki dakikada bir kontrol eden bir systemd timer kurar: tünel adresi değiştiyse `miner.env`'i
güncelleyip worker'ı yeniden başlatır, worker ölmüşse kaldırır, uzun süre iş gelmemişse
log'a uyarı yazar.

---

## `status` çıktısını okuma

Miner'ın iki normal çalışma hali var ve ikisi farklı satırlar üretir:

- **Kalibrasyon aşaması** → `answered task` satırları (ghost işleri)
- **Üretim aşaması** → `[session] open` satırları ve `Not polling mempool tasks`

Kalibre olmuş bir miner ghost işlerine **dönmez**. Sadece `answered task` arayıp bulamazsanız
miner'ınızı bozuk sanabilirsiniz; `status` bu ayrımı yapıyor.

---

## Bu araç çalışırken bulduğumuz tuzaklar

Hepsi gerçek bir kurulumda karşımıza çıktı ve script'te ele alınıyor.

| Belirti | Sebep |
|---|---|
| `evet` yazıyorsunuz, kurulum "iptal edildi" diyor | `screen` içinde trackpad ile kaydırmak aşağı-ok dizilerini (`ESC[B`) girdiye yazıyor; ekranda görünmüyorlar |
| Kurulum sonunda tünel `502` dönüyor | Kontrol worker'dan önce yapılırsa tünel ayakta olsa da 8645'i dinleyen yoktur |
| `Failed to initialize NVML: Driver/library version mismatch` | Arka planda sürücü güncellenmiş, çekirdek modülü eski kalmış. Çözüm: `reboot` |
| `unknown option '--suri-file'` | CLI v0.1.290'da argüman kaldırıldı. Adresi worker'ın `Signer:` satırından okuyun |
| `Enclave key file must be a regular file` | Docker, bind-mount edilen dosya yoksa o yola **klasör** yaratıyor |
| Dosyayı düzelttiniz ama worker hâlâ çöküyor | Bind-mount konteyner yaratılırken çözülüyor; `--force-recreate` gerekiyor |
| `Signer: 5Grwva...` | `signer` okunamadı, worker herkese açık `//Alice` test hesabına düştü. Madencilik size işlemiyor |
| `Unsupported runtime spec version` | CLI zincirin gerisinde. Taze kurulumda güncel sürüm geliyor |

---

## Teşekkür ve kapsam

Bu araç, [@UfukDegen](https://x.com/UfukDegen)'in
[flop-miner-setup](https://github.com/UfukNode/flop-miner-setup) reposundaki Compose
dosyalarını ve ayar şablonunu kullanıyor. Sürümleri kendimiz sabitlemiyoruz, oradan miras
alıyoruz - zincir güncellendiğinde o repo takip edildiği için taze kurulumlar doğru sürümü
otomatik çekiyor.

**Adım adım elle kurulum öğrenmek istiyorsanız** Ufuk'un rehberi bu işin referans metni,
İngilizce ve Türkçe: [flop-miner-setup](https://github.com/UfukNode/flop-miner-setup).
Bu repo onun yerine geçmiyor; o rehberin otomasyonu.


**Kapsam dışı:** hybrid miner, controller upgrade, çoklu GPU, validator. Araç tek GPU
modelinde (RTX 5060 Ti 16 GB) test edildi.

---

## Resmî kaynaklar

Buradaki her şeyi aşağıdan doğrulayın. Çelişki görürseniz resmî kaynak geçerlidir -
issue açın, düzeltelim.

- [flop.finance/official](https://flop.finance/official/) - resmî link listesi
- [docs.flop.network/docs/run-miner](https://docs.flop.network/docs/run-miner)
- [explorer.devnet.flop.network/mining](https://explorer.devnet.flop.network/mining)
- [flop.network/releases.json](https://flop.network/releases.json) - sürüm listesi (zincirin gerisinde kalabiliyor)
- [github.com/flop-labs/network](https://github.com/flop-labs/network) - hata bildirimi

---

## Uyarı

Devnet bir test ağıdır: ödül yoktur, token'lar değersizdir, zincir sıfırlanabilir.
GPU kiralama, disk ve internet maliyeti size aittir. Bu araç yatırım tavsiyesi değildir ve
resmî bir FLOP Labs ürünü değildir.

FLOP hiçbir zaman seed phrase'inizi istemez. "Satın al", "claim et", "mint et" diyen her şey
dolandırıcılıktır. Henüz FLOP token'ı yoktur.

Vast.ai linki referans linkidir.

---

*Bir adım sizde farklı davrandıysa issue açın - araç kullanan herkesin deneyimiyle güncelleniyor.*
