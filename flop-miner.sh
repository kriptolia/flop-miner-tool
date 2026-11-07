#!/usr/bin/env bash
# FLOP Devnet GPU miner kurulumu — KriptoliaTR
#
#   bash flop-miner.sh check    → on kontrol (MAKINE KIRALAMADAN ONCE calistirin)
#   bash flop-miner.sh install  → tam kurulum
#   bash flop-miner.sh status   → mevcut kurulumun durumu
#   bash flop-miner.sh restore  → mevcut anahtarla YENI makineye tasima
#   bash flop-miner.sh watch    → tunel/worker nobetcisi kur (systemd timer)
#
# Devnet odul vermez, airdrop agirligi tasidigina dair resmi aciklama yoktur,
# zincir sifirlanabilir. Resmi linkler: https://flop.finance/official/
#
# Dogrulama damgasi: 2026-11-07 / worker 0.1.238 / CLI 0.1.220 / runtime spec 1014014
set -uo pipefail

DIR=/opt/flop-miner
REPO=https://github.com/UfukNode/flop-miner-setup.git
MODEL_HASH=0x1a52c1abe781db051e70ae357f72bb70161ca0c092df0b618f22a9292ba63306
RPC=wss://rpc.devnet.flop.network
SPONSOR_URL=https://faucet.flop.network
EXPLORER=https://explorer.devnet.flop.network/mining
WORKER_MIN=0.1.172      # explorer "Worker minimum" degeri — guncelligini kontrol edin

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
ok()   { printf '   \033[32m[OK]\033[0m %s\n' "$*"; }
warn() { printf '   \033[33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\n\033[31m[HATA]\033[0m %s\n\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- on kontrol
preflight() {
  local fail=0

  say "1/4  GPU"
  if ! command -v nvidia-smi >/dev/null; then
    warn "nvidia-smi yok. Bu makinede NVIDIA surucusu kurulu degil."; fail=1
  elif ! nvidia-smi -L >/dev/null 2>&1; then
    # Surucu kutuphaneleri guncellenip cekirdek modulu eski kalinca NVML
    # acilmiyor. Bu kontrol olmazsa hata metni kart adi ve VRAM degeri
    # sanilip ekrana basiliyor, kullanici ne oldugunu anlamiyor.
    # Ciktiyi once degiskene al: pipefail yuzunden "nvidia-smi | grep"
    # hep basarisiz donuyor ve asagidaki tavsiye hic basilmiyor.
    local nverr; nverr=$(nvidia-smi -L 2>&1 | head -1)
    warn "nvidia-smi calismiyor: $nverr"
    case "$nverr" in
      *[Vv]ersion\ mismatch*)
        warn "Surucu/cekirdek modulu uyusmazligi. Makineyi yeniden baslatin:  reboot"
        warn "Yeniden baslattiktan sonra ayni komutu tekrar calistirin." ;;
    esac
    fail=1
  else
    local name drv vram vfree
    name=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)
    drv=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)
    vram=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1)
    vfree=$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits | head -1)
    printf '   Kart: %s | Surucu: %s | VRAM: %s MiB (bos: %s MiB)\n' "$name" "$drv" "$vram" "$vfree"
    [ "${drv%%.*}" -ge 580 ] 2>/dev/null \
      && ok "Surucu yeterli (580+)" \
      || { warn "Surucu 580'in altinda. Backend bu makinede calismaz."; fail=1; }
    [ "$vram" -ge 15000 ] 2>/dev/null \
      && ok "VRAM yeterli (16 GB+)" \
      || { warn "VRAM 16 GB'in altinda."; fail=1; }
    # Toplam VRAM yetse bile karti baska bir surec tutuyorsa backend bir saat
    # sonra OOM ile patliyor. Kart gercekten bos mu, simdi bakalim.
    if [ "${vfree:-0}" -ge 14000 ] 2>/dev/null; then
      ok "Kart bos"
    elif [ -d "$DIR" ] && docker ps --format '{{.Names}}' 2>/dev/null | grep -q flop-miner; then
      ok "Kart kullanimda ama kullanan bu kurulumun kendisi"
    else
      warn "Kartin $vfree MiB'i bos. Baska bir surec/instance karti tutuyor."
      warn "Backend bu makinede acilmaz. Baska makine kiralayin."; fail=1
    fi
  fi

  say "2/4  Docker"
  if command -v docker >/dev/null && docker compose version >/dev/null 2>&1; then
    ok "Docker ve Compose kurulu"
  else
    warn "Docker veya Compose eksik. Vast.ai'de 'VM' etiketli sablonu secin."; fail=1
  fi

  say "3/4  Disk"
  local free; free=$(df -BG --output=avail / | tail -1 | tr -dc '0-9')
  printf '   Bos alan: %s GB\n' "$free"
  [ "$free" -ge 45 ] 2>/dev/null \
    && ok "Disk yeterli" \
    || { warn "45 GB'den az bos alan var. Kurulum ~32 GB kullaniyor."; fail=1; }

  say "4/4  Sponsor servisi"
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "$SPONSOR_URL/chain" 2>/dev/null) || code=000
  case "$code" in
    200) ok "Servis ayakta (HTTP 200)" ;;
    000) warn "Servise ulasilamadi. Kiralamadan once tekrar deneyin." ; fail=1 ;;
    *)   warn "Servis $code donuyor. Su an saglikli degil, kiralamayi erteleyin." ; fail=1 ;;
  esac
  printf '   Not: kuyrugun dolu olup olmadigi ancak kayit denenince belli olur.\n'
  printf '   Dolu gelirse kurulum DURMAZ; arka planda beklenir, kalan adimlar tamamlanir.\n'

  echo
  if [ "$fail" -ne 0 ]; then
    printf '\033[31mBu makine veya bu an uygun degil.\033[0m\n\n'
    return 1
  fi
  printf '\033[32mUygun. Kuruluma gecebilirsiniz:\033[0m  bash %s install\n\n' "$0"
  return 0
}

# ---------------------------------------------------------------- yardimcilar
need_root() { [ "$(id -u)" -eq 0 ] || die "Bu script root olarak calistirilmali."; }
compose() { docker compose --env-file "$DIR/miner.env" -f "$DIR/docker-compose.yml" "$@"; }
flopcli() { docker run --rm --network host -v "$DIR:/work" "$FLOP_CLI" "$@"; }

ver_ge() {  # ver_ge A B  → A >= B ise 0
  [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" = "$2" ]
}

# Docker, bind-mount edilen bir dosya host'ta yoksa o yola KLASOR yaratiyor.
# Konteyner bir kez enclave.seed olmadan baslarsa dosya yerine klasor olusuyor
# ve worker "Enclave key file must be a regular file" diyip surekli cokuyor;
# 8645 dinlenmedigi icin tunel de 502 donuyor. Tek kaynaktan hallediyoruz.
ensure_enclave_seed() {
  local f="$DIR/session-keys/enclave.seed"
  install -d -m 700 "$DIR/session-keys"
  if [ -d "$f" ]; then
    rmdir "$f" 2>/dev/null || rm -rf "$f"
    warn "enclave.seed dosya yerine klasordu (Docker yaratmis), silindi."
    # Docker bind-mount'u konteyner YARATILIRKEN cozuyor. Dosyayi duzeltmek
    # mevcut konteyneri duzeltmez; yeniden yaratilmasi sart, yoksa worker
    # ayni hatayla cokmeye devam eder.
    ENCLAVE_REPAIRED=1
  fi
  if [ ! -s "$f" ]; then
    sh -c "umask 077; openssl rand -hex 32 > '$f'" || die "enclave.seed yazilamadi."
    ENCLAVE_NEW=1
  else
    ENCLAVE_NEW=0
  fi
  [ -f "$f" ] || die "enclave.seed olusturulamadi: $f"
}

# ---------------------------------------------------------------- adimlar
step_toolkit() {
  say "NVIDIA Container Toolkit"
  if docker run --rm --gpus all nvidia/cuda:13.0.1-base-ubuntu22.04 nvidia-smi -L >/dev/null 2>&1; then
    ok "Zaten kurulu, GPU Docker icinden gorunuyor"; return
  fi
  apt-get update -qq
  apt-get install -y -qq nvidia-container-toolkit >/dev/null
  nvidia-ctk runtime configure --runtime=docker >/dev/null
  systemctl restart docker
  sleep 3
  docker run --rm --gpus all nvidia/cuda:13.0.1-base-ubuntu22.04 nvidia-smi -L >/dev/null 2>&1 \
    || die "GPU hala Docker icinden gorunmuyor."
  ok "Kuruldu ve dogrulandi"
}

step_files() {
  say "Dosyalar ve ayar"
  mkdir -p "$DIR/models"
  if [ ! -f "$DIR/miner.env" ]; then
    local tmp; tmp=$(mktemp -d)
    git clone -q "$REPO" "$tmp/src" || die "Repo indirilemedi."
    cp "$tmp/src/docker-compose.yml" "$tmp/src/miner.env.example" "$tmp/src/sponsor.mjs" "$DIR/"
    rm -rf "$tmp"
    install -m 600 "$DIR/miner.env.example" "$DIR/miner.env"
    sed -i "s|^INFERENCE_API_KEY=.*|INFERENCE_API_KEY=$(openssl rand -hex 32)|" "$DIR/miner.env"
    sed -i "s|^SESSION_AUTH_TOKEN=.*|SESSION_AUTH_TOKEN=$(openssl rand -hex 32)|" "$DIR/miner.env"
    sed -i "s|^WORKER_NAME=.*|WORKER_NAME=${WORKER_NAME:-miner-$(head -c3 /dev/urandom | xxd -p)}|" "$DIR/miner.env"
    ok "miner.env olusturuldu (WORKER_NAME=$(grep ^WORKER_NAME= "$DIR/miner.env" | cut -d= -f2))"
  else
    ok "miner.env zaten var, dokunulmadi"
  fi
  FLOP_CLI=$(grep '^FLOP_CLI=' "$DIR/miner.env" | cut -d= -f2-)
  [ -n "$FLOP_CLI" ] || die "miner.env icinde FLOP_CLI bulunamadi."
  export FLOP_CLI
  ok "CLI: ${FLOP_CLI##*/}"
  case "$FLOP_CLI" in
    *v0.1.220*) warn "Bu CLI surumu devnet runtime 1014014 ile calismiyor."
                warn "Repo guncellenmemis olabilir: $REPO" ;;
  esac

  # worker surumu agin kabul ettigi tabanin altinda mi?
  local wv
  wv=$(grep -oE 'worker:[0-9]+\.[0-9]+\.[0-9]+' "$DIR/docker-compose.yml" | head -1 | cut -d: -f2)
  if [ -n "$wv" ]; then
    if ver_ge "$wv" "$WORKER_MIN"; then
      ok "Worker surumu $wv (taban $WORKER_MIN)"
    else
      warn "Worker surumu $wv, agin tabani $WORKER_MIN. Ag bu worker'i reddedebilir."
      warn "Guncel tabani $EXPLORER sayfasinda 'Worker minimum' satirindan kontrol edin."
    fi
  fi
}

step_images() {
  say "Imajlar indiriliyor (~23 GB, sabir)"
  docker pull -q "$FLOP_CLI" >/dev/null
  compose pull -q
  ok "Indirildi"
}

step_keys() {
  say "Miner anahtari"
  if [ -s "$DIR/signer" ]; then
    ok "signer dosyasi zaten var, yeni anahtar uretilmedi"
  else
    umask 077
    local kf; kf=$(mktemp)
    flopcli keys generate --type sr25519 --show-secret --json > "$kf" || die "Anahtar uretilemedi."
    jq -r .mnemonic "$kf" > "$DIR/signer"; chmod 600 "$DIR/signer"
    MINER_ADDR=$(jq -r .address "$kf"); rm -f "$kf"
    echo
    printf '\033[33m=====================  24 KELIME  =====================\033[0m\n'
    cat "$DIR/signer"
    printf '\033[33m=======================================================\033[0m\n'
    printf 'Bu kelimeler hesabinizin kendisidir.\n'
    printf 'KAGIDA YAZIN. Hicbir sohbete, mesaja, nota, yapay zekaya yapistirmayin.\n'
    printf 'Devnet degersiz olabilir; aliskanligi burada dogru kurun.\n\n'
    # Bekleme sirasinda biriken girdiyi at. screen/tmux icinde trackpad ile
    # kaydirmak asagi-ok dizilerini (ESC[B) stdin'e yaziyor; bunlar ekranda
    # gorunmuyor ama cevaba yapisip gecerli bir "evet"i reddettiriyor.
    while read -r -t 0.1 -n 4096 _drain 2>/dev/null; do :; done
    read -r -p 'Kagida yazdim, devam et (yazin: evet): ' c || c=""
    # Once ANSI kacis dizilerini sil, sonra harf disi her seyi.
    c=$(printf '%s' "${c:-}" \
        | sed $'s/\033\\[[0-9;?]*[A-Za-z~]//g' \
        | tr -cd '[:alpha:]' | tr '[:upper:]' '[:lower:]')
    case "$c" in
      *evet*|*tamam*|*onay*|*yes*|*ok*|e|y) ;;
      *) die "Iptal edildi (okunan cevap: '${c}'). Kelimeler $DIR/signer icinde duruyor.
   Devam etmek icin ayni komutu tekrar calistirin; uretilen anahtar korunur.
   Terminal girdisi bozuksa:  printf 'evet\\n' | bash $0 install" ;;
    esac
    clear
  fi
  # MINER_ADDR, anahtar yeni uretildiyse yukarida "keys generate" ciktisindan
  # geldi. Mevcut bir signer'la calisiyorsak bos kalir ve worker'in "Signer:"
  # satirindan dogrulanir — CLI argumanlari surumden surume degistigi icin
  # adresi burada turetmeye calismiyoruz.
  ensure_enclave_seed
  ok "Anahtarlar hazir${MINER_ADDR:+ (adres: $MINER_ADDR)}"
}

step_model() {
  say "Model indirme ve dogrulama"
  if [ -f "$DIR/models/qwen2.5-0.5b-instruct/model.safetensors" ]; then
    ok "Model zaten indirilmis"; return
  fi
  local i
  for i in 1 2 3; do
    if flopcli --network devnet --rpc "$RPC" model fetch "$MODEL_HASH" \
         --precision BF16 --output-dir /work/models/qwen2.5-0.5b-instruct --json \
         | tee /tmp/model.json | grep -q '"ok": true'; then
      ok "Model dogrulandi (zincirdeki hash ile eslesti)"; return
    fi
    warn "Deneme $i basarisiz, tekrar deneniyor..."; sleep 10
  done
  die "Model dogrulanamadi. Komutu elle calistirip cevaba bakin."
}

step_backend() {
  say "Backend baslatiliyor (model GPU'ya yukleniyor)"
  compose up -d backend
  local i
  for i in $(seq 1 60); do
    if compose exec -T backend python3 -c 'import os,urllib.request as u; u.urlopen(u.Request("http://127.0.0.1:8000/health",headers={"Authorization":"Bearer "+os.environ["INFERENCE_API_KEY"]}))' >/dev/null 2>&1; then
      ok "Backend hazir"; return
    fi
    sleep 10
  done
  die "Backend 10 dakikada acilmadi. Log: compose logs --tail 50 backend"
}

step_tunnel() {
  say "HTTPS tuneli"
  command -v cloudflared >/dev/null || {
    curl -fsSL -o /tmp/cf.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
    dpkg -i /tmp/cf.deb >/dev/null 2>&1
  }
  if ! systemctl is-active --quiet flop-tunnel; then
    cat > /etc/systemd/system/flop-tunnel.service <<'UNIT'
[Unit]
Description=FLOP miner HTTPS tunnel
After=network-online.target
Wants=network-online.target
[Service]
ExecStart=/usr/bin/cloudflared tunnel --no-autoupdate --url http://127.0.0.1:8645
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
UNIT
    systemctl daemon-reload
    systemctl enable --now flop-tunnel >/dev/null 2>&1
  fi
  local h i
  for i in $(seq 1 20); do
    h=$(journalctl -u flop-tunnel --no-pager 2>/dev/null | grep -o '[a-z0-9-]*\.trycloudflare\.com' | tail -1)
    [ -n "$h" ] && break
    sleep 3
  done
  [ -n "$h" ] || die "Tunel adresi alinamadi. journalctl -u flop-tunnel ile bakin."
  sed -i "s|^SESSION_PUBLIC_HOST=.*|SESSION_PUBLIC_HOST=$h|" "$DIR/miner.env"
  TUNNEL_HOST=$h
  ok "Tunel: $h"
}

ALICE=5GrwvaEF5zXb26Fz9rcQpDWS57CtERHpNehXCPcNoHGKutQY

step_worker() {
  say "Worker baslatiliyor"
  if [ "${ENCLAVE_REPAIRED:-0}" = "1" ]; then
    warn "enclave.seed onarildi, worker yeniden yaratiliyor (--force-recreate)."
    compose up -d --force-recreate worker
  else
    compose up -d worker
  fi
  # Worker cokup yeniden baslayabiliyor; tek sefer bakmak yerine bekleyelim.
  local signer i
  for i in $(seq 1 12); do
    sleep 5
    signer=$(compose logs worker 2>/dev/null | grep -m1 'Signer:' | awk '{print $NF}')
    [ -n "$signer" ] && break
  done

  if [ -z "$signer" ]; then
    warn "Signer satiri 60 saniyede gorunmedi. Worker cokuyor olabilir:"
    warn "  docker compose --env-file $DIR/miner.env -f $DIR/docker-compose.yml logs --tail 20 worker"
  elif [ "$signer" = "$ALICE" ]; then
    # signer dosyasi okunamazsa worker sessizce herkese acik test hesabina
    # dusuyor: her sey calisiyor gorunuyor ama madencilik size islemiyor.
    die "Worker //Alice test hesabina dusmus ($signer).
   $DIR/signer dosyasini kontrol edin: var mi, bos mu, izni 600 mu?"
  elif [ -n "${MINER_ADDR:-}" ] && [ "$signer" != "$MINER_ADDR" ]; then
    die "Signer satiri ($signer) uretilen adresle ($MINER_ADDR) eslesmiyor."
  else
    ok "Signer: $signer"
    MINER_ADDR=$signer
  fi

  compose logs worker 2>/dev/null | grep -q 'model-gate OK' && ok "model-gate OK"
  compose logs worker 2>/dev/null | grep -q 'mailbox' && ok "Tunel adresi aga duyuruldu"
}

# Tunelin dis kontrolu WORKER AYAGA KALKTIKTAN SONRA yapilmali: 8645'i
# dinleyen worker'dir. Worker'dan once sorulursa tunel ayakta olsa bile
# 502 doner ve kullanici saglam bir kurulumu bozuk sanir.
step_tunnel_check() {
  say "Tunel dis erisim kontrolu"
  local code i
  for i in $(seq 1 12); do
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 \
           "https://$TUNNEL_HOST/session/info" 2>/dev/null) || code=000
    [ "$code" = "401" ] && break
    sleep 5
  done
  if [ "$code" = "401" ]; then
    ok "Disaridan erisilebilir (401 beklenen cevap)"
  else
    warn "Disaridan $code donuyor, 401 bekleniyordu."
    case "$code" in
      502) warn "502 = tunel ayakta ama worker 8645'i dinlemiyor."
           warn "Worker cokuyor olabilir:"
           warn "  docker compose --env-file $DIR/miner.env -f $DIR/docker-compose.yml logs --tail 20 worker" ;;
      000) warn "000 = tunele hic ulasilamiyor. systemctl status flop-tunnel" ;;
    esac
    warn "Birkac dakika sonra elle kontrol edin:"
    warn "  curl -s -o /dev/null -w '%{http_code}\\n' https://$TUNNEL_HOST/session/info"
  fi
}

# Sponsor EN SON calisir ve BLOKE ETMEZ: kuyruk doluysa arka planda beklenir,
# makine bu arada tamamen hazir durur. Slot acildiginda kalibrasyon
# kendiliginden baslar ve ~12 dakikada tamamlanir.
step_sponsor_bg() {
  say "Sponsor kaydi (arka plan)"
  local out
  out=$(docker run --rm -v "$DIR:/work" --entrypoint node "$FLOP_CLI" /work/sponsor.mjs 2>&1)
  if grep -q '"success":true' <<<"$out"; then
    printf '%s  *** SPONSOR OK ***\n' "$(date -u '+%H:%M:%SZ')" >> /root/sponsor.log
    ok "Kayit ilk denemede gecti, stake yatirildi"
    SPONSOR_DONE=1
    return
  fi
  SPONSOR_DONE=0
  if grep -q auto_miner_cap_full <<<"$out"; then
    SPONSOR_STATE=cap_full
    warn "Kuyruk dolu (en fazla 40 kalibre olmamis sponsorlu miner)."
  else
    SPONSOR_STATE=down
    warn "Sponsor servisi su an cevap vermiyor (kuyruk dolu oldugu icin degil)."
  fi

  cat > /root/sponsor-loop.sh <<'EOF'
#!/bin/bash
export FLOP_CLI=$(grep '^FLOP_CLI=' /opt/flop-miner/miner.env | cut -d= -f2-)
while :; do
  ts=$(date -u '+%H:%M:%SZ')
  out=$(docker run --rm -v /opt/flop-miner:/work --entrypoint node "$FLOP_CLI" /work/sponsor.mjs 2>&1)
  if grep -q '"success":true' <<<"$out"; then
    echo "$ts  *** SPONSOR OK ***" >> /root/sponsor.log; break
  elif grep -q auto_miner_cap_full <<<"$out"; then
    echo "$ts  cap_full" >> /root/sponsor.log
  elif grep -qi 'cloudflare\|524\|timeout' <<<"$out"; then
    echo "$ts  524" >> /root/sponsor.log
  else
    echo "$ts  ? $(tr '\n' ' ' <<<"$out" | cut -c1-150)" >> /root/sponsor.log
  fi
  sleep $((75 + RANDOM % 30))
done
EOF
  chmod +x /root/sponsor-loop.sh
  pkill -f sponsor-loop.sh 2>/dev/null
  nohup /root/sponsor-loop.sh > /dev/null 2>&1 &
  ok "Arka plan dongusu basladi (PID $!), ~90 saniyede bir deniyor"
  printf '   Takip: tail -3 /root/sponsor.log\n'
  printf '   Dongu SSH kopsa da, siz bilgisayarinizi kapatsaniz da calisir.\n'
}

# ---------------------------------------------------------------- restore
# Devnet'te makineler oluyor: bakiye bitiyor, Destroy ediliyor, host dusuyor.
# Hesap zincirde kaliyor — stake, kayit ve kalibrasyon orada. Yeni makinede
# SPONSOR ADIMI TEKRARLANMAMALI: her hesap yalnizca bir kez sponsorlanir,
# tekrar denemek kuyrugu bosuna mesgul eder.
step_keys_existing() {
  say "Mevcut miner anahtari"
  if [ ! -s "$DIR/signer" ]; then
    printf '\n'
    printf '   %s dosyasi yok. 24 kelimenizi oraya koymadan devam edilemez.\n' "$DIR/signer"
    printf '\n   Kendi bilgisayarinizda yedeginiz varsa (onerilen):\n'
    printf '     scp -P <PORT> ~/flop-signer-yedek.txt root@<IP>:%s/signer\n' "$DIR"
    printf '\n   Yoksa sunucuda elle olusturun (kelimeler TEK SATIR, aralarinda bosluk):\n'
    printf '     mkdir -p %s && umask 077\n' "$DIR"
    printf '     cat > %s/signer\n' "$DIR"
    printf '     <24 kelimeyi yazin, Enter, sonra Ctrl+D>\n'
    printf '     chmod 600 %s/signer\n\n' "$DIR"
    die "signer dosyasi bulunamadi."
  fi
  ok "signer bulundu"
  # Adresi CLI ile turetmiyoruz: "keys inspect" surumden surume degisiyor
  # (v0.1.290'da --suri-file kaldirildi, artik keystore JSON istiyor).
  # Adres worker'in kendi "Signer:" satirindan okunacak — tek dogruluk kaynagi.
  MINER_ADDR=""
  printf '   Adres, worker ayaga kalkinca log satirindan dogrulanacak.\n'
  ensure_enclave_seed
  if [ "${ENCLAVE_NEW:-0}" = "1" ]; then
    warn "enclave.seed yoktu, yenisi uretildi. Worker yeni ghost anahtarini duyuracak."
    warn "Bir dahakine signer ile birlikte enclave.seed'i de yedekleyin."
  else
    ok "enclave.seed mevcut"
  fi
}

# ---------------------------------------------------------------- watch
# Ucretsiz Cloudflare tuneli her yeniden basladiginda YENI adres aliyor.
# Adres degisince miner'in aga duyurdugu adres oluyor: hicbir hata mesaji
# cikmiyor, her sey calisiyor gorunuyor, ama is gelmiyor. 600 blok icinde
# cevaplanmayan is stake'ten kesiliyor. Bu nobetci tam olarak bunu yakalar.
install_watch() {
  [ -f "$DIR/miner.env" ] || die "Kurulum bulunamadi ($DIR/miner.env yok)."
  say "Nobetci kuruluyor"

  cat > /usr/local/bin/flop-watch.sh <<'WATCH'
#!/bin/bash
DIR=/opt/flop-miner
LOG=/root/flop-watch.log
ts() { date -u '+%Y-%m-%d %H:%M:%SZ'; }
compose() { docker compose --env-file "$DIR/miner.env" -f "$DIR/docker-compose.yml" "$@"; }

cur=$(grep '^SESSION_PUBLIC_HOST=' "$DIR/miner.env" 2>/dev/null | cut -d= -f2)
new=$(journalctl -u flop-tunnel --no-pager 2>/dev/null \
      | grep -o '[a-z0-9-]*\.trycloudflare\.com' | tail -1)

if [ -n "$new" ] && [ -n "$cur" ] && [ "$new" != "$cur" ]; then
  sed -i "s|^SESSION_PUBLIC_HOST=.*|SESSION_PUBLIC_HOST=$new|" "$DIR/miner.env"
  compose up -d worker >/dev/null 2>&1
  echo "$(ts)  tunel adresi degisti: $cur -> $new ; worker yeniden baslatildi" >> "$LOG"
  exit 0
fi

if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q flop-miner-worker; then
  compose up -d worker >/dev/null 2>&1
  echo "$(ts)  worker kapaliydi, yeniden baslatildi" >> "$LOG"
  exit 0
fi

n=$(compose logs --since 20m worker 2>/dev/null | grep -c 'answered task')
if [ "${n:-0}" -eq 0 ]; then
  echo "$(ts)  UYARI: son 20 dakikada cevaplanan is yok" >> "$LOG"
fi
WATCH
  chmod +x /usr/local/bin/flop-watch.sh

  cat > /etc/systemd/system/flop-watch.service <<'UNIT'
[Unit]
Description=FLOP miner nobetcisi (tunel adresi ve worker)
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/flop-watch.sh
UNIT

  cat > /etc/systemd/system/flop-watch.timer <<'UNIT'
[Unit]
Description=FLOP miner nobetcisini 2 dakikada bir calistir
[Timer]
OnBootSec=2min
OnUnitActiveSec=2min
AccuracySec=15s
[Install]
WantedBy=timers.target
UNIT

  systemctl daemon-reload
  systemctl enable --now flop-watch.timer >/dev/null 2>&1
  printf '%s  nobetci kuruldu\n' "$(date -u '+%Y-%m-%d %H:%M:%SZ')" >> /root/flop-watch.log
  /usr/local/bin/flop-watch.sh
  ok "Nobetci kuruldu, 2 dakikada bir kontrol ediyor"
  printf '   Log    : tail -5 /root/flop-watch.log\n'
  printf '   Durum  : systemctl status flop-watch.timer\n'
  printf '   Kapat  : systemctl disable --now flop-watch.timer\n'
}

show_status() {
  FLOP_CLI=$(grep '^FLOP_CLI=' "$DIR/miner.env" 2>/dev/null | cut -d= -f2-)
  [ -n "$FLOP_CLI" ] || die "Kurulum bulunamadi ($DIR/miner.env yok)."
  export FLOP_CLI
  local addr host
  addr=$(compose logs worker 2>/dev/null | grep -m1 'Signer:' | awk '{print $NF}')
  host=$(grep '^SESSION_PUBLIC_HOST=' "$DIR/miner.env" | cut -d= -f2)

  say "Durum"
  printf '   Adres : %s\n   Tunel : https://%s\n' "${addr:-bilinmiyor}" "$host"
  compose ps

  say "Sponsor"
  if [ -f /root/sponsor.log ]; then
    tail -3 /root/sponsor.log
    grep -q 'SPONSOR OK' /root/sponsor.log && ok "Sponsor kaydi gecmis"
  else
    printf '   Log yok.\n'
  fi
  pgrep -f sponsor-loop.sh >/dev/null && printf '   Arka plan dongusu calisiyor.\n'

  say "Kalibrasyon ve is akisi"
  local cap ghosts sessions
  cap=$(compose logs worker 2>/dev/null | grep -i 'cap accepted' | tail -1)
  ghosts=$(compose logs worker 2>/dev/null | grep -c 'answered task')
  sessions=$(compose logs worker 2>/dev/null | grep -c '\[session\] open')

  if [ -n "$cap" ]; then printf '  %s\n' "$cap"; else
    printf '   Henuz "cap accepted" satiri yok (kalibrasyon surüyor olabilir).\n'
  fi

  # Kalibre olmus bir miner ghost islerine DONMEZ: "Session-serving mode"a
  # gecip oturum sunar. Sadece "answered task" aramak, calisan bir miner'i
  # bozuk gosterir.
  if [ "${sessions:-0}" -gt 0 ]; then
    printf '   Oturum sunma modu: %s oturum acildi (kalibrasyon bitmis, uretimde).\n' "$sessions"
    compose logs worker 2>/dev/null | grep '\[session\] open' | tail -2
  elif [ "${ghosts:-0}" -gt 0 ]; then
    printf '   Kalibrasyon isleri: %s cevaplanan is.\n' "$ghosts"
    compose logs worker 2>/dev/null | grep 'answered task' | tail -2
  else
    printf '   Henuz is gelmemis. Yeni kurulumda birkac dakika normaldir.\n'
  fi

  say "Nobetci"
  if systemctl is-active --quiet flop-watch.timer 2>/dev/null; then
    printf '   Calisiyor (2 dakikada bir kontrol).\n'
    if [ -s /root/flop-watch.log ]; then
      tail -3 /root/flop-watch.log
    else
      printf '   Mudahale gerektiren bir durum olmadi.\n'
    fi
  else
    printf '   KURULU DEGIL. Tunel adresi degisirse miner sessizce agdan kopar:\n'
    printf '   hata mesaji cikmaz, is gelmez, 600 blok sonra stake kesilir.\n'
    printf '   Kurmak icin:  bash %s watch\n' "$0"
  fi

  echo
  printf '   Zincir tarafi: %s\n' "$EXPLORER"
  printf '   (adresinizi aratip STATUS ve VERSION sutunlarina bakin)\n'
}

# ---------------------------------------------------------------- akis
MODE=${1:-}
case "$MODE" in
  check)   preflight; exit $? ;;
  status)  show_status; exit 0 ;;
  watch)   need_root; FLOP_CLI=$(grep '^FLOP_CLI=' "$DIR/miner.env" 2>/dev/null | cut -d= -f2-)
           export FLOP_CLI; install_watch; exit 0 ;;
  install|restore) ;;
  *) printf 'Kullanim: bash %s {check|install|restore|watch|status}\n\n' "$0"
     printf '  check    makine kiralamadan once calistirin\n'
     printf '  install  sifirdan tam kurulum\n'
     printf '  restore  mevcut 24 kelimeyle yeni makineye tasima (sponsor ATLANIR)\n'
     printf '  watch    tunel/worker nobetcisi kur\n'
     printf '  status   mevcut durumu goster\n'
     exit 1 ;;
esac

need_root

# Kurulum ~1 saat suruyor. SSH koparsa on planda calisan kurulum da olur.
if [ -z "${STY:-}" ] && [ -z "${TMUX:-}" ] && [ -t 1 ]; then
  warn "screen/tmux disinda calisiyorsunuz. SSH koparsa kurulum yarida kalir."
  warn "Onerilen:  apt-get install -y screen && screen -S flop"
  warn "Sonra bu komutu screen icinde calistirin. (Devam icin 5 sn bekleniyor)"
  sleep 5
fi

preflight || die "On kontrol basarisiz."

# restore'da anahtari EN BASTA sor. Imajlari cektikten sonra sormak,
# anahtari olmayan kullaniciyi bos yere 20 dakika bekletiyor.
if [ "$MODE" = "restore" ] && [ ! -s "$DIR/signer" ]; then
  printf '\n'
  printf '   %s dosyasi yok. 24 kelimenizi oraya koymadan devam edilemez.\n' "$DIR/signer"
  printf '\n   Kendi bilgisayarinizda yedeginiz varsa (onerilen):\n'
  printf '     scp -P <PORT> ~/flop-signer-yedek.txt root@<IP>:%s/signer\n' "$DIR"
  printf '\n   Yoksa sunucuda elle olusturun (kelimeler TEK SATIR, aralarinda bosluk):\n'
  printf '     mkdir -p %s && umask 077\n' "$DIR"
  printf '     cat > %s/signer\n' "$DIR"
  printf '     <24 kelimeyi yazin, Enter, sonra Ctrl+D>\n'
  printf '     chmod 600 %s/signer\n\n' "$DIR"
  die "signer dosyasi bulunamadi. Hicbir sey indirilmedi."
fi

command -v jq >/dev/null || { apt-get update -qq && apt-get install -y -qq jq >/dev/null; }
step_toolkit
step_files
step_images
if [ "$MODE" = "restore" ]; then step_keys_existing; else step_keys; fi
step_model
step_backend
step_tunnel
step_worker
step_tunnel_check
[ "$MODE" = "restore" ] || step_sponsor_bg

cat <<EOF

================================================================
  Kurulum tamam. Makine hazir.

  Durum:        bash $0 status
  Nobetci:      bash $0 watch      (onerilir: tunel adresi degisirse yakalar)
  Worker logu:  docker compose --env-file $DIR/miner.env \\
                  -f $DIR/docker-compose.yml logs -f worker

EOF

if [ "$MODE" = "restore" ]; then
cat <<EOF
  TASIMA tamamlandi. Sponsor adimi bilerek ATLANDI: her hesap yalnizca
  bir kez sponsorlanir, hesabiniz zaten kayitli ve kalibrasyonu zincirde.
  Worker birkac dakika icinde is almaya baslamali.

  Dogrulama: $EXPLORER
  adresinizi aratin; STATUS sutununda kayit ve online isaretlerini arayin.
EOF
elif [ "${SPONSOR_DONE:-0}" = "1" ]; then
cat <<EOF
  Sponsor kaydi gecti. Kalibrasyon ~12 dakikada kendiliginden tamamlanir.
  "cap accepted" satirini bekleyin.
EOF
elif [ "${SPONSOR_STATE:-}" = "cap_full" ]; then
cat <<EOF
  Sponsor kuyrugu su an DOLU. BEKLEMENIZE GEREK YOK:
  arka plan dongusu ~90 saniyede bir deniyor, slot acilinca kayit gecer
  ve kalibrasyon ~12 dakikada kendiliginden tamamlanir.
  Makineyi acik birakin; bilgisayarinizi kapatabilirsiniz.
  Kuyruk bazen dakikalar, bazen saatler suruyor (bizde bir kez 19.5 saat
  surdu, ertesi gun ayni islem 90 saniyede gecti). Normaldir, beklemeyin.
EOF
else
cat <<EOF
  Sponsor servisi ilk denemede CEVAP VERMEDI. Bu kuyrugun dolu oldugu
  anlamina gelmez; servis gecici olarak erisilemez durumda.
  Arka plan dongusu ~90 saniyede bir tekrar deniyor, genelde birkac
  denemede geciyor. Yapmaniz gereken bir sey yok.

  Kontrol:  tail -3 /root/sponsor.log
EOF
fi

cat <<EOF

  Zincir tarafi: $EXPLORER

  ONEMLI: Worker'i acik tutun. Gonderilen is 600 blok icinde
  cevaplanmazsa stake'ten kesinti yapilir.
  Makineyi birakirken Destroy edin; Stop disk ucretini durdurmaz.
================================================================

EOF
