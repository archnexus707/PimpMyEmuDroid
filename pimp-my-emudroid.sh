#!/usr/bin/env bash
# ==============================================================================
#  ____  _                 __  __         _____              ____            _     _
# |  _ \(_)_ __ ___  _ __ |  \/  |_   _  | ____|_ __ ___  _ |  _ \ _ __ ___ (_) __| |
# | |_) | | '_ ` _ \| '_ \| |\/| | | | | |  _| | '_ ` _ \| || | | | '__/ _ \| |/ _` |
# |  __/| | | | | | | |_) | |  | | |_| | | |___| | | | | | || |_| | | | (_) | | (_| |
# |_|   |_|_| |_| |_| .__/|_|  |_|\__, | |_____|_| |_| |_|_||____/|_|  \___/|_|\__,_|
#                   |_|           |___/
#
#   PIMP MY EMUDROID  —  QEMU Android pentest-lab provisioner
#   Author : archnexus707
#   License: for authorized security testing / education only
# ==============================================================================
set -o pipefail
IFS=$'\n\t'

# ------------------------------------------------------------------ metadata --
readonly PME_VERSION="1.1.1"
readonly PME_AUTHOR="archnexus707"
LAB_DIR="${PME_LAB_DIR:-$HOME/Desktop/QEMU}"
CONFIG_DIR="$HOME/.config/pimp-my-emudroid"
CONFIG_FILE="$CONFIG_DIR/config.env"
LOG_FILE="$CONFIG_DIR/pme.log"
THEME="${PME_THEME:-neon}"

# --------------------------------------------------------------------- colors --
readonly ESC=$'\033'
readonly RESET="${ESC}[0m" BOLD="${ESC}[1m" DIM="${ESC}[2m" ITAL="${ESC}[3m"
rgb()   { printf "${ESC}[38;2;%d;%d;%dm" "$1" "$2" "$3"; }
bg()    { printf "${ESC}[48;2;%d;%d;%dm" "$1" "$2" "$3"; }

# theme palettes: primary / secondary / accent (start->end gradient rgb pairs)
theme_palette() {
  case "$THEME" in
    matrix)   G1=(0 255 65);   G2=(0 120 30);   ACC=(180 255 180); INK=(120 200 120);;
    synthwave)G1=(255 60 180); G2=(90 90 255);  ACC=(255 220 60);  INK=(200 140 220);;
    *)        G1=(0 240 255);  G2=(180 60 255);  ACC=(80 255 140);  INK=(130 150 200);; # neon
  esac
}
theme_palette

C_OK="$(rgb 80 255 140)"; C_WARN="$(rgb 255 200 60)"; C_ERR="$(rgb 255 80 90)"
C_INK="$(rgb 150 160 190)"; C_ACC="$(rgb "${ACC[@]}")"; C_MUT="$(rgb 90 95 120)"

# gradient text: $1 = string, colored char-by-char from G1 -> G2
grad() {
  local s="$1" n=${#1} i r g b t
  ((n<=1)) && n=2
  for ((i=0;i<${#s};i++)); do
    t=$(( i * 100 / (n-1) ))
    r=$(( G1[0] + (G2[0]-G1[0])*t/100 ))
    g=$(( G1[1] + (G2[1]-G1[1])*t/100 ))
    b=$(( G1[2] + (G2[2]-G1[2])*t/100 ))
    printf "%s%s" "$(rgb $r $g $b)" "${s:i:1}"
  done
  printf "%s" "$RESET"
}

# ----------------------------------------------------------------- utilities --
log()  { mkdir -p "$CONFIG_DIR"; printf '[%s] %s\n' "$(date '+%F %T' 2>/dev/null || echo ts)" "$1" >>"$LOG_FILE" 2>/dev/null; }
line() { printf "%s" "$C_MUT"; printf '─%.0s' $(seq 1 "${1:-64}"); printf "%s\n" "$RESET"; }
ok()   { printf "  ${C_OK}✔${RESET} %s\n" "$1"; log "OK: $1"; }
warn() { printf "  ${C_WARN}▲${RESET} %s\n" "$1"; log "WARN: $1"; }
err()  { printf "  ${C_ERR}✘${RESET} %s\n" "$1"; log "ERR: $1"; }
step() { printf "  ${C_ACC}▸${RESET} %s\n" "$1"; log "STEP: $1"; }
note() { printf "    ${C_MUT}%s${RESET}\n" "$1"; }
pause(){ printf "\n  ${C_MUT}press ${RESET}${BOLD}ENTER${RESET}${C_MUT} to continue…${RESET}"; read -r _; }

# spinner: spin "message" -- command args...
spin() {
  local msg="$1"; shift
  local frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' i=0
  ( "$@" ) & local pid=$!
  tput civis 2>/dev/null
  while kill -0 "$pid" 2>/dev/null; do
    i=$(((i+1)%10))
    printf "\r  ${C_ACC}%s${RESET} %s" "${frames:i:1}" "$msg"
    sleep 0.08
  done
  wait "$pid"; local rc=$?
  tput cnorm 2>/dev/null
  if ((rc==0)); then printf "\r  ${C_OK}✔${RESET} %s\033[K\n" "$msg"
  else printf "\r  ${C_ERR}✘${RESET} %s\033[K\n" "$msg"; fi
  return $rc
}

# arrow-key menu: menu "Title" opt1 opt2 ... -> sets $MENU_CHOICE (0-based)
menu() {
  local title="$1"; shift
  local -a opts=("$@"); local sel=0 key n=${#opts[@]} i
  printf "\n  ${BOLD}%s${RESET}\n" "$title"
  tput civis 2>/dev/null
  while true; do
    for ((i=0;i<n;i++)); do
      if ((i==sel)); then
        printf "  ${C_ACC}▶ ${BOLD}%s${RESET}\033[K\n" "${opts[i]}"
      else
        printf "    ${C_INK}%s${RESET}\033[K\n" "${opts[i]}"
      fi
    done
    IFS= read -rsn1 key
    if [[ $key == $ESC ]]; then read -rsn2 -t 0.05 key2 2>/dev/null; key+="$key2"; fi
    case "$key" in
      $ESC'[A'|'k') ((sel=(sel-1+n)%n));;
      $ESC'[B'|'j') ((sel=(sel+1)%n));;
      ''|$'\n') break;;
      [1-9]) (( key<=n )) && { sel=$((key-1)); break; };;
      q|Q) sel=-1; break;;
    esac
    printf "\033[%dA" "$n"   # move cursor back up to redraw
  done
  tput cnorm 2>/dev/null
  MENU_CHOICE=$sel
}

confirm() { # confirm "question"  -> returns 0 for yes
  local q="$1" a
  printf "  ${C_WARN}?${RESET} %s ${C_MUT}[y/N]${RESET} " "$q"
  read -r a; [[ $a =~ ^[Yy]$ ]]
}

have() { command -v "$1" >/dev/null 2>&1; }

# ------------------------------------------------------------------- banner ---
banner() {
  clear
  local title
  if have figlet; then title="$(figlet -f small 'EmuDroid' 2>/dev/null)"; fi
  printf '\n'
  printf "  %s\n" "$(grad '╔══════════════════════════════════════════════════════════╗')"
  if [[ -n ${title:-} ]]; then
    while IFS= read -r l; do printf "  %s  %s\n" "$(grad '║')" "$(grad "$l")"; done <<<"$title"
  fi
  printf "  %s   %sP I M P   M Y   E m u D r o i d%s\n" "$(grad '║')" "$BOLD$C_ACC" "$RESET"
  printf "  %s   %sQEMU Android pentest-lab provisioner%s\n" "$(grad '║')" "$C_INK" "$RESET"
  printf "  %s   %sv%s  ·  by %s%s%s\n" "$(grad '║')" "$C_MUT" "$PME_VERSION" "$BOLD" "$PME_AUTHOR" "$RESET"
  printf "  %s\n" "$(grad '╚══════════════════════════════════════════════════════════╝')"
  printf "  ${C_MUT}${ITAL}for authorized security testing & education only${RESET}\n\n"
}

# -------------------------------------------------------------- spec scanner --
declare -g CPU_MODEL CPU_CORES RAM_GB DISK_FREE_GB HAS_VIRT HAS_KVM KVM_RW ARCH
scan_specs() {
  ARCH=$(uname -m)
  CPU_MODEL=$(sed -n 's/^model name[[:space:]]*: //p' /proc/cpuinfo 2>/dev/null | head -1)
  [[ -z $CPU_MODEL ]] && CPU_MODEL="unknown"
  CPU_CORES=$(nproc 2>/dev/null || echo 1)
  RAM_GB=$(awk '/MemTotal/{printf "%.1f",$2/1048576}' /proc/meminfo 2>/dev/null)
  DISK_FREE_GB=$(df -Pk "$LAB_DIR" 2>/dev/null | awk 'NR==2{printf "%.0f",$4/1048576}')
  [[ -z $DISK_FREE_GB ]] && DISK_FREE_GB=$(df -Pk "$HOME" | awk 'NR==2{printf "%.0f",$4/1048576}')
  grep -Eqc '(vmx|svm)' /proc/cpuinfo 2>/dev/null && HAS_VIRT=1 || HAS_VIRT=0
  [[ -e /dev/kvm ]] && HAS_KVM=1 || HAS_KVM=0
  { [[ -r /dev/kvm && -w /dev/kvm ]] && KVM_RW=1; } || KVM_RW=0
}

scan_screen() {
  banner
  printf "  %s\n" "$(grad '━━━  SYSTEM SCAN  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━')"
  echo
  local rows=(
    "CPU|$CPU_MODEL"
    "Cores / threads|$CPU_CORES"
    "Architecture|$ARCH"
    "Memory|${RAM_GB} GB"
    "Free disk ($LAB_DIR)|${DISK_FREE_GB} GB"
  )
  local r k v
  for r in "${rows[@]}"; do
    k=${r%%|*}; v=${r#*|}
    spin "probing ${k}…" sleep 0.15
    printf "\033[1A\r  ${C_ACC}▸${RESET} %-22s ${BOLD}%s${RESET}\033[K\n" "$k" "$v"
  done
  # virtualization verdict
  if ((HAS_VIRT)); then ok "CPU virtualization (VT-x/AMD-V) supported"; else err "No CPU virtualization — emulation will be SLOW"; fi
  if ((HAS_KVM)); then
    if ((KVM_RW)); then ok "/dev/kvm present and accessible (KVM acceleration ready)"
    else warn "/dev/kvm present but not accessible — add yourself to the 'kvm' group"; fi
  else err "/dev/kvm missing — install/enable KVM for acceleration"; fi
  echo
}

# ----------------------------------------------------- recommendation engine --
# emulator catalog:  key | label | android | iso-url | approx-size | min-ram-gb | note
catalog() {
  cat <<'EOF'
ax9|Android-x86 9.0-r2 (x86_64)|Android 9 (Pie)|https://downloads.sourceforge.net/project/android-x86/Release%209.0/android-x86_64-9.0-r2.iso|0.9 GB|2|Lightweight, fast under KVM. ARM-only apps need a houdini addon.
ax81|Android-x86 8.1-r6 (x86_64)|Android 8.1 (Oreo)|https://downloads.sourceforge.net/project/android-x86/Release%208.1/android-x86_64-8.1-r6.iso|0.8 GB|2|Even lighter; older API. Good for very low-RAM rigs.
bliss|Bliss OS 14+ (manual URL)|Android 12-14|MANUAL|~2 GB|6|Modern Android + ARM translation. You paste the ISO URL from blissos.org.
custom|Custom ISO (local file/URL)|any|CUSTOM|-|2|Provide your own Android-x86/Bliss ISO path or URL.
EOF
}

declare -g REC_KEY REC_REASON REC_VM_RAM REC_VM_CPU
recommend() {
  local ram_int=${RAM_GB%.*}
  # VM cpu = half the cores, min 2, max 4
  REC_VM_CPU=$(( CPU_CORES/2 )); ((REC_VM_CPU<2)) && REC_VM_CPU=2; ((REC_VM_CPU>4)) && REC_VM_CPU=4
  if   (( ram_int >= 12 )); then REC_KEY=bliss; REC_VM_RAM=4096
       REC_REASON="You have ${RAM_GB} GB — plenty for a modern Android 12-14 image with ARM translation."
  elif (( ram_int >= 8 ));  then REC_KEY=ax9;   REC_VM_RAM=3072
       REC_REASON="${RAM_GB} GB is comfortable for Android-x86 9 with headroom for Burp + Frida."
  elif (( ram_int >= 5 ));  then REC_KEY=ax9;   REC_VM_RAM=2048
       REC_REASON="${RAM_GB} GB is modest, so a light Android 9 image (2 GB VM) keeps Burp usable alongside."
  else                            REC_KEY=ax81;  REC_VM_RAM=1536
       REC_REASON="Only ${RAM_GB} GB — the lightest Oreo image at 1.5 GB is the safe choice."
  fi
  ((HAS_KVM==0 || HAS_VIRT==0)) && REC_REASON+=" NOTE: no KVM — expect slow performance whichever you pick."
}

rec_screen() {
  local key label android url size minram note found
  while IFS='|' read -r key label android url size minram note; do
    [[ $key == "$REC_KEY" ]] && { found="$label|$android|$size|$note"; break; }
  done < <(catalog)
  printf "  %s\n" "$(grad '━━━  RECOMMENDATION  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━')"
  echo
  printf "  ${C_ACC}★ Best match for this rig:${RESET} ${BOLD}%s${RESET}\n" "${found%%|*}"
  printf "    ${C_INK}%s${RESET}\n" "$REC_REASON"
  echo
  printf "    ${C_MUT}Android version :${RESET} %s\n" "$(echo "$found" | cut -d'|' -f2)"
  printf "    ${C_MUT}Download size   :${RESET} %s\n" "$(echo "$found" | cut -d'|' -f3)"
  printf "    ${C_MUT}Suggested VM    :${RESET} %s MB RAM · %s vCPU\n" "$REC_VM_RAM" "$REC_VM_CPU"
  printf "    ${C_MUT}Heads-up        :${RESET} %s\n" "$(echo "$found" | cut -d'|' -f4)"
  echo
}

# -------------------------------------------------------- dependency doctor ---
# name | binary | apt-package | installer(apt|pipx|special)
deps_list() {
  cat <<'EOF'
QEMU system|qemu-system-x86_64|qemu-system-x86|apt
QEMU tools|qemu-img|qemu-utils|apt
ADB|adb|android-sdk-platform-tools|apt
aapt|aapt|aapt|apt
OpenSSL|openssl|openssl|apt
wget|wget|wget|apt
xz|xz|xz-utils|apt
pipx|pipx|pipx|apt
Frida tools|frida|frida-tools|pipx
jadx (optional)|jadx|jadx|apt
apktool (optional)|apktool|apktool|apt
EOF
}

doctor_check() { # returns list of missing "name|pkg|installer"
  MISSING=()
  local name bin pkg via
  while IFS='|' read -r name bin pkg via; do
    if have "$bin"; then ok "$(printf '%-18s %s' "$name" "$(command -v "$bin")")"
    else err "$(printf '%-18s missing' "$name")"; MISSING+=("$name|$pkg|$via"); fi
  done < <(deps_list)
}

doctor_install() {
  ((${#MISSING[@]}==0)) && { ok "All dependencies satisfied."; return 0; }
  echo; warn "${#MISSING[@]} missing dependency(ies)."
  local apt_pkgs=() pipx_pkgs=() m name pkg via
  for m in "${MISSING[@]}"; do
    IFS='|' read -r name pkg via <<<"$m"
    [[ $via == apt ]] && apt_pkgs+=("$pkg")
    [[ $via == pipx ]] && pipx_pkgs+=("$pkg")
  done
  if ! have apt-get; then err "Non-apt system — install manually: ${apt_pkgs[*]} ${pipx_pkgs[*]}"; return 1; fi
  confirm "Install missing packages now (uses sudo)?" || { note "skipped."; return 1; }
  if ((${#apt_pkgs[@]})); then
    step "apt: ${apt_pkgs[*]}"
    sudo apt-get update -y && sudo apt-get install -y "${apt_pkgs[@]}" || warn "apt step had errors (see output)"
  fi
  if ((${#pipx_pkgs[@]})); then
    have pipx || { sudo apt-get install -y pipx; }
    for p in "${pipx_pkgs[@]}"; do
      if [[ $p == frida-tools ]]; then
        step "pipx: frida-tools (pinned to 16.x for script compatibility)"
        pipx install --force "frida-tools==13.7.1" || warn "frida-tools install issue"
      else
        step "pipx: $p"; pipx install "$p"
      fi
    done
    export PATH="$HOME/.local/bin:$PATH"
  fi
  ok "Dependency install pass complete."
}

# --------------------------------------------------------- emulator provision -
choose_emulator() {
  local -a keys labels; local key label rest
  while IFS='|' read -r key label rest; do keys+=("$key"); labels+=("$label"); done < <(catalog)
  # put recommended first-marked
  local -a display=()
  local i
  for i in "${!keys[@]}"; do
    if [[ ${keys[i]} == "$REC_KEY" ]]; then display+=("${labels[i]}  ★ recommended"); else display+=("${labels[i]}"); fi
  done
  menu "Choose an Android image to provision:" "${display[@]}" "‹ back"
  (( MENU_CHOICE<0 || MENU_CHOICE>=${#keys[@]} )) && { CHOSEN_KEY=""; return; }
  CHOSEN_KEY="${keys[MENU_CHOICE]}"
}

provision_emulator() {
  mkdir -p "$LAB_DIR"; cd "$LAB_DIR" || return 1
  local key="$1" url label size iso disk
  local ln; ln=$(catalog | awk -F'|' -v k="$key" '$1==k')
  label=$(cut -d'|' -f2 <<<"$ln"); url=$(cut -d'|' -f4 <<<"$ln")
  disk="$LAB_DIR/${key}.qcow2"; iso="$LAB_DIR/${key}.iso"

  if [[ $url == MANUAL || $url == CUSTOM ]]; then
    printf "  ${C_WARN}?${RESET} Paste ISO URL or local path: "; read -r url
    [[ -z $url ]] && { err "no URL given"; return 1; }
  fi

  # obtain ISO
  if [[ -f $url ]]; then
    step "Using local ISO: $url"; iso="$url"
  elif [[ -f $iso ]]; then
    ok "ISO already present: $iso"
  else
    step "Downloading $label"
    if ! wget -c --tries=3 -O "$iso" "$url"; then err "download failed"; return 1; fi
  fi
  file "$iso" 2>/dev/null | grep -qi 'ISO 9660\|DOS/MBR' || warn "downloaded file may not be a valid ISO — verify it"

  # disk
  local dsize="${PME_DISK_SIZE:-12G}"
  if [[ -f $disk ]]; then ok "Disk exists: $disk"
  else spin "creating ${dsize} virtual disk" qemu-img create -f qcow2 "$disk" "$dsize"; fi

  gen_run_scripts "$key" "$iso" "$disk"
  save_config
  echo
  ok "Provisioned '$label'."
  note "Install:  cd '$LAB_DIR' && ./pme-install-${key}.sh   (once)"
  note "Run:      ./pme-run-${key}.sh"
  note "Connect:  ./pme-connect.sh"
}

gen_run_scripts() {
  local key="$1" iso="$2" disk="$3" ram="$REC_VM_RAM" cpu="$REC_VM_CPU"
  cat >"$LAB_DIR/pme-install-${key}.sh" <<EOF
#!/usr/bin/env bash
# [Pimp My EmuDroid] one-time installer for ${key}
cd "\$(dirname "\$0")"
qemu-system-x86_64 -enable-kvm -cpu host -smp ${cpu} -m ${ram} \\
  -name "PME install ${key}" -hda "${disk##*/}" -cdrom "${iso##*/}" -boot d \\
  -vga std -net nic,model=virtio -net user -machine q35 -usbdevice tablet
EOF
  cat >"$LAB_DIR/pme-run-${key}.sh" <<EOF
#!/usr/bin/env bash
# [Pimp My EmuDroid] boot installed ${key}; forwards :5555 for adb
cd "\$(dirname "\$0")"
qemu-system-x86_64 -enable-kvm -cpu host -smp ${cpu} -m ${ram} \\
  -name "PME ${key}" -hda "${disk##*/}" -boot c -vga std \\
  -device virtio-net-pci,netdev=net0 \\
  -netdev user,id=net0,hostfwd=tcp::5555-:5555 -machine q35 -usbdevice tablet
EOF
  # connect helper (generic)
  cat >"$LAB_DIR/pme-connect.sh" <<'EOF'
#!/usr/bin/env bash
# [Pimp My EmuDroid] post-boot: adb connect, root, frida-server, forwards
set -uo pipefail; cd "$(dirname "$0")"
D="localhost:5555"; FS="/data/local/tmp/frida-server"
LOCAL=$(ls frida-server-*-android-x86_64 2>/dev/null | grep -v '\.xz$' | sort -V | tail -1)
export PATH="$HOME/.local/bin:$PATH"
echo "[*] adb connect"; adb connect "$D" >/dev/null
for i in $(seq 1 30); do [ "$(adb -s "$D" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ] && break; sleep 2; done
adb -s "$D" root >/dev/null 2>&1; sleep 2; adb connect "$D" >/dev/null 2>&1
# keep the display awake (stop the black-screen sleep) and wake it now
adb -s "$D" shell settings put system screen_off_timeout 2147483647 >/dev/null 2>&1
adb -s "$D" shell settings put global stay_on_while_plugged_in 7 >/dev/null 2>&1
adb -s "$D" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1
if [ -n "$LOCAL" ]; then
  adb -s "$D" shell ls "$FS" >/dev/null 2>&1 || { adb -s "$D" push "$LOCAL" "$FS" >/dev/null; adb -s "$D" shell chmod 755 "$FS"; }
  adb -s "$D" shell "ps -A 2>/dev/null | grep -q frida-server" || adb -s "$D" shell "setsid $FS >/dev/null 2>&1 < /dev/null &"
  adb -s "$D" forward tcp:27042 tcp:27042 >/dev/null; adb -s "$D" forward tcp:27043 tcp:27043 >/dev/null
fi
echo "[*] root : $(adb -s "$D" shell id 2>/dev/null | tr -d '\r')"
echo "[*] proxy: $(adb -s "$D" shell settings get global http_proxy 2>/dev/null | tr -d '\r')"
command -v frida-ps >/dev/null && frida-ps -H localhost:27042 2>/dev/null | head -5
echo "[+] ready."
EOF
  chmod +x "$LAB_DIR/pme-install-${key}.sh" "$LAB_DIR/pme-run-${key}.sh" "$LAB_DIR/pme-connect.sh"
}

# --------------------------------------------------------------- frida setup --
setup_frida() {
  export PATH="$HOME/.local/bin:$PATH"
  if ! have frida; then
    warn "frida not installed."
    confirm "Install frida-tools (16.x, script-compatible)?" && pipx install --force "frida-tools==13.7.1"
    export PATH="$HOME/.local/bin:$PATH"
  fi
  have frida || { err "frida still missing"; return 1; }
  local ver; ver=$(frida --version 2>/dev/null)
  ok "Host Frida: $ver"
  local server="$LAB_DIR/frida-server-${ver}-android-x86_64"
  if [[ -f $server ]]; then ok "Matching frida-server present."; else
    step "Fetching frida-server ${ver} (android-x86_64)"
    local u="https://github.com/frida/frida/releases/download/${ver}/frida-server-${ver}-android-x86_64.xz"
    if spin "downloading frida-server ${ver}" wget -q -O "${server}.xz" "$u"; then
      unxz -f "${server}.xz" && chmod +x "$server" && ok "frida-server ready: ${server##*/}"
    else err "could not fetch frida-server ${ver} — check the version exists on GitHub"; fi
  fi
  # bundle the universal pinning-bypass script
  [[ -f "$LAB_DIR/pinning-bypass.js" ]] || write_pinning_script
  ok "pinning-bypass.js available in $LAB_DIR"
}

write_pinning_script() {
  cat >"$LAB_DIR/pinning-bypass.js" <<'EOF'
// [Pimp My EmuDroid] universal Android SSL pinning bypass (Frida 16.x)
Java.perform(function () {
  var L = function (m) { console.log('[pme-unpin] ' + m); };
  try { var CP = Java.use('okhttp3.CertificatePinner');
    CP.check.overload('java.lang.String','java.util.List').implementation=function(a,b){L('OkHttp bypass '+a);}; } catch(e){}
  try {
    var X=Java.use('javax.net.ssl.X509TrustManager'), S=Java.use('javax.net.ssl.SSLContext');
    var TM=Java.registerClass({name:'com.pme.TrustAll',implements:[X],methods:{checkClientTrusted:function(){},checkServerTrusted:function(){},getAcceptedIssuers:function(){return[];}}});
    var init=S.init.overload('[Ljavax.net.ssl.KeyManager;','[Ljavax.net.ssl.TrustManager;','java.security.SecureRandom');
    init.implementation=function(k,t,r){L('SSLContext trust-all');init.call(this,k,[TM.$new()],r);};
  } catch(e){L('TM skip '+e);}
  try { var A=Java.use('java.util.ArrayList'), T=Java.use('com.android.org.conscrypt.TrustManagerImpl');
    T.checkTrustedRecursive.implementation=function(){L('Conscrypt bypass');return A.$new();}; } catch(e){}
  L('hooks installed');
});
EOF
}

# ------------------------------------------------------ unattended installer -
extract_boot() { # key iso  ->  sets KERNEL_IMG / INITRD_IMG
  local key="$1" iso="$2" dst="$LAB_DIR/.pme_boot/$key"
  mkdir -p "$dst"; KERNEL_IMG="$dst/kernel"; INITRD_IMG="$dst/initrd.img"
  [[ -f $KERNEL_IMG && -f $INITRD_IMG ]] && return 0
  if have 7z;   then 7z x -y -o"$dst" "$iso" kernel initrd.img >/dev/null 2>&1
  elif have xorriso; then xorriso -osirrox on -indev "$iso" -extract /kernel "$KERNEL_IMG" -extract /initrd.img "$INITRD_IMG" >/dev/null 2>&1; fi
  [[ -f $KERNEL_IMG && -f $INITRD_IMG ]]
}

auto_install() { # key
  local key="$1"
  case "$key" in ax9|ax81) ;; *) err "Unattended install supports Android-x86 images only. Use the manual installer for '$key'."; return 1;; esac
  local iso="$LAB_DIR/${key}.iso" disk="$LAB_DIR/${key}.qcow2" ram="${REC_VM_RAM:-2048}" cpu="${REC_VM_CPU:-2}"
  [[ -f $iso ]]  || { err "ISO for $key not found — provision it first (menu → Provision)."; return 1; }
  [[ -f $disk ]] || { err "Disk for $key not found — provision it first."; return 1; }
  warn "AUTO-INSTALL will ERASE and reinstall ${disk##*/} (the throwaway VM disk)."
  note "Zero manual menus: auto-partition → format ext4 → install GRUB."
  note "Tradeoff: /system stays READ-ONLY. HTTPS interception still works via Frida."
  note "For a system-trusted Burp CA, use the manual installer and pick '/system R-W = Yes'."
  confirm "Proceed with unattended auto-install?" || { note "cancelled."; return 1; }

  spin "extracting kernel + initrd from ISO" extract_boot "$key" "$iso" || { err "could not extract boot files"; return 1; }
  if confirm "Recreate a fresh blank disk first (recommended)?"; then
    local dsize="${PME_DISK_SIZE:-12G}"; rm -f "$disk"
    spin "creating fresh ${dsize} disk" qemu-img create -f qcow2 "$disk" "$dsize"
  fi

  local kvm=(); ((KVM_RW)) && kvm=(-enable-kvm -cpu host)
  step "Launching unattended installer — a QEMU window shows live progress."
  log "auto-install start key=$key"
  qemu-system-x86_64 "${kvm[@]}" -smp "$cpu" -m "$ram" \
    -name "PME auto-install ${key}" \
    -kernel "$KERNEL_IMG" -initrd "$INITRD_IMG" \
    -append "root=/dev/ram0 AUTO_INSTALL=1 SRC= DEBUG=" \
    -hda "$disk" -cdrom "$iso" \
    -vga std -no-reboot -machine q35 -usbdevice tablet >/dev/null 2>&1 &
  local qpid=$! frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' i=0 waited=0 max=900
  tput civis 2>/dev/null
  while kill -0 "$qpid" 2>/dev/null; do
    i=$(((i+1)%10)); printf "\r  ${C_ACC}%s${RESET} installing… %ss  ${C_MUT}(watch the window; it closes when done)${RESET}\033[K" "${frames:i:1}" "$waited"
    sleep 1; ((waited++)); ((waited>=max)) && break
  done
  tput cnorm 2>/dev/null; printf "\r\033[K"
  if kill -0 "$qpid" 2>/dev/null; then
    err "Still running after ${max}s. Check the QEMU window; if it says 'installed successfully', close it, then boot with ./pme-run-${key}.sh"
    return 1
  fi
  ok "Installer finished (QEMU exited on the post-install reboot)."
  note "Boot the installed system:  ./pme-run-${key}.sh"
  note "Then wire it up:            ./pme-connect.sh"
}

# ---------------------------------------------------- APK static analysis ----
_sec() { printf "\n  ${BOLD}%s${RESET}\n" "$1"; }
apk_analyze() { # apk-path [deep]
  local apk="$1" deep="${2:-}"
  [[ -f $apk ]] || { err "APK not found: $apk"; return 1; }
  have aapt || { err "aapt missing — run the Dependency Doctor."; return 1; }
  local outdir="$LAB_DIR/apk-reports"; mkdir -p "$outdir"
  local tmp; tmp=$(mktemp -d "${TMPDIR:-/tmp}/pme-apk.XXXXXX")
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN

  local badging pkg ver vc sdkmin sdktgt abis dbg
  badging=$(aapt dump badging "$apk" 2>/dev/null)
  pkg=$(sed -n "s/.*package: name='\([^']*\)'.*/\1/p" <<<"$badging" | head -1)
  ver=$(sed -n "s/.*versionName='\([^']*\)'.*/\1/p" <<<"$badging" | head -1)
  vc=$(sed -n "s/.*versionCode='\([^']*\)'.*/\1/p" <<<"$badging" | head -1)
  sdkmin=$(sed -n "s/sdkVersion:'\([0-9]*\)'/\1/p" <<<"$badging" | head -1)
  sdktgt=$(sed -n "s/targetSdkVersion:'\([0-9]*\)'/\1/p" <<<"$badging" | head -1)
  abis=$(sed -n "s/native-code: //p" <<<"$badging" | head -1); [[ -z $abis ]] && abis="(none / pure-dalvik)"
  grep -q 'application-debuggable' <<<"$badging" && dbg="YES — debuggable build!" || dbg="no"

  banner
  printf "  %s\n" "$(grad '━━━  APK STATIC ANALYSIS  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━')"
  printf "  ${C_MUT}%s${RESET}\n" "$apk"

  _sec "Identity"
  printf "    package        %s\n" "${pkg:-?}"
  printf "    version        %s (code %s)\n" "${ver:-?}" "${vc:-?}"
  printf "    minSdk/target  %s / %s\n" "${sdkmin:-?}" "${sdktgt:-?}"
  printf "    ABIs           %s\n" "$abis"
  if grep -qE 'x86_64|x86' <<<"$abis" || [[ $abis == *pure-dalvik* ]]; then
    ok "runs on your x86_64 Android-x86 VM"
  else warn "ARM-only native libs — needs ARM translation (houdini) or a Bliss OS VM"; fi

  _sec "Signing (apksigner)"
  if have apksigner; then
    local sg; sg=$(apksigner verify --print-certs -v "$apk" 2>/dev/null)
    if [[ -n $sg ]]; then
      printf "    %s\n" "$(grep -E 'Verified using v[0-9]' <<<"$sg" | sed 's/^/  /')"
      printf "    signer: %s\n" "$(grep -m1 'Signer #1 certificate DN' <<<"$sg" | sed 's/.*DN: //')"
      printf "    SHA-256: %s\n" "$(grep -m1 'SHA-256 digest' <<<"$sg" | sed 's/.*: //')"
      grep -qE 'v1 scheme .*true' <<<"$sg" && grep -qE 'v2 scheme .*false' <<<"$sg" && warn "v1-only signing (Janus-class risk on old Android)"
    else warn "apksigner could not read a signature"; fi
  else note "apksigner not installed (optional)"; fi

  # decode manifest + smali
  step "decoding with apktool…"
  if ! apktool d -f -q -o "$tmp/d" "$apk" >/dev/null 2>&1; then
    warn "apktool decode failed; continuing with aapt data only"
  fi
  local M="$tmp/d/AndroidManifest.xml"

  _sec "Manifest risk flags"
  local f
  for f in debuggable allowBackup usesCleartextTraffic; do
    local v; v=$(grep -oE "android:$f=\"[^\"]*\"" "$M" 2>/dev/null | head -1 | sed 's/.*="//;s/"//')
    case "$f:$v" in
      debuggable:true)          err  "android:debuggable=\"true\" (debug build in the wild)";;
      allowBackup:true)         warn "android:allowBackup=\"true\" (adb backup can exfil app data)";;
      usesCleartextTraffic:true)warn "android:usesCleartextTraffic=\"true\" (HTTP allowed)";;
      *) [[ -n $v ]] && note "android:$f=\"$v\"";;
    esac
  done
  grep -q 'networkSecurityConfig' "$M" 2>/dev/null && note "custom networkSecurityConfig present (inspect res/xml)"

  _sec "Exported components (reachable by other apps)"
  if [[ -f $M ]]; then
    grep -oE '<(activity|activity-alias|service|receiver|provider)[^>]*android:exported="true"[^>]*' "$M" \
      | grep -oE 'android:name="[^"]*"' | sed 's/android:name="/    · /;s/"$//' | sort -u | head -25
    grep -oE '<provider[^>]*android:exported="true"[^>]*' "$M" >/dev/null 2>&1 && warn "exported content provider(s) — check for path traversal / SQLi"
  else note "manifest unavailable"; fi

  _sec "Notable permissions"
  local DANGER='INSTALL_PACKAGES|DELETE_PACKAGES|ACCESS_SUPERUSER|REQUEST_INSTALL_PACKAGES|MANAGE_EXTERNAL_STORAGE|SYSTEM_ALERT_WINDOW|READ_SMS|SEND_SMS|RECEIVE_SMS|READ_CONTACTS|RECORD_AUDIO|CAMERA|ACCESS_FINE_LOCATION|READ_CALL_LOG|BIND_ACCESSIBILITY_SERVICE|WRITE_SETTINGS|QUERY_ALL_PACKAGES'
  local perms; perms=$(grep "uses-permission:" <<<"$badging" | sed "s/.*name='//;s/'.*//")
  local p hit=0
  while IFS= read -r p; do
    if grep -qE "\.($DANGER)$" <<<"$p"; then printf "  ${C_WARN}▲${RESET} %s\n" "$p"; hit=1; fi
  done <<<"$perms"
  ((hit==0)) && note "no high-risk permissions flagged"
  printf "    ${C_MUT}(%s permissions total)${RESET}\n" "$(grep -c 'uses-permission:' <<<"$badging")"

  _sec "Hardcoded secrets / endpoints"
  local sources=("$tmp/d/res/values" "$tmp/d/smali" "$tmp/d/assets"); local sroots=()
  for s in "${sources[@]}"; do compgen -G "${s}*" >/dev/null 2>&1 && sroots+=("$s"*); done
  # fall back to raw APK strings if decode failed
  local rawstr=""; [[ ${#sroots[@]} -eq 0 ]] && rawstr=1
  local URL_NOISE='schemas\.android\.com|w3\.org|apache\.org|xmlpull\.org|java\.sun\.com|purl\.org|iana\.org|ns\.adobe\.com|whatwg\.org|slf4j\.org|json-schema\.org|specs/web'
  scan_secret() { # label regex [exclude-regex]
    local label="$1" rx="$2" excl="${3:-}" out
    if [[ -n $rawstr ]]; then out=$(unzip -p "$apk" 2>/dev/null | strings | grep -aoE "$rx")
    else out=$(grep -rhoE "$rx" "${sroots[@]}" 2>/dev/null); fi
    [[ -n $excl ]] && out=$(grep -vE "$excl" <<<"$out")
    out=$(sort -u <<<"$out" | grep -v '^$' | head -6)
    [[ -n $out ]] && { printf "  ${C_WARN}▲${RESET} %s:\n" "$label"; sed 's/^/      /' <<<"$out"; SECRETS_HIT=1; }
  }
  local SECRETS_HIT=0
  scan_secret "Google API key"   'AIza[0-9A-Za-z_\-]{35}'
  scan_secret "AWS access key"   'AKIA[0-9A-Z]{16}'
  scan_secret "Firebase DB URL"  'https://[a-z0-9.-]+\.firebaseio\.com'
  scan_secret "Private key block" '-----BEGIN [A-Z ]*PRIVATE KEY-----'
  scan_secret "JWT"              'eyJ[A-Za-z0-9_-]{6,}\.eyJ[A-Za-z0-9_-]{6,}\.[A-Za-z0-9_-]{6,}'
  scan_secret "Cleartext http URL" 'http://[a-zA-Z0-9./_-]{6,}' "$URL_NOISE"
  ((SECRETS_HIT==0)) && note "no obvious hardcoded secrets or cleartext endpoints"
  note "Reminder: Google/Firebase keys are meant to ship in APKs — only a finding if unrestricted."

  if [[ -n $deep ]] && have jadx; then
    _sec "Deep decompile (jadx)"
    spin "jadx → java (this takes a bit)" jadx -d "$tmp/jadx" "$apk"
    ok "Java sources at: $tmp/jadx (copied to report dir)"; cp -r "$tmp/jadx" "$outdir/${pkg:-unknown}-jadx" 2>/dev/null
  fi

  # save a plain-text report
  local report="$outdir/${pkg:-unknown}.txt"
  { echo "Pimp My EmuDroid — APK report"; echo "file: $apk"; echo "package: $pkg  version: $ver ($vc)"
    echo "minSdk/target: $sdkmin/$sdktgt  ABIs: $abis  debuggable: $dbg"; echo
    echo "== exported components =="; grep -oE '<(activity|service|receiver|provider)[^>]*android:exported="true"[^>]*' "$M" 2>/dev/null | grep -oE 'android:name="[^"]*"' | sort -u
    echo; echo "== permissions =="; echo "$perms"; } >"$report" 2>/dev/null
  echo; ok "Full report saved: $report"
  printf "  ${C_MUT}All local — nothing was sent anywhere. Only analyze apps you're authorized to test.${RESET}\n"
}

# ------------------------------------------------------- burp CA auto-install -
auto_burp() {
  cd "$LAB_DIR" || return 1
  local D="localhost:5555"
  adb connect "$D" >/dev/null 2>&1
  adb -s "$D" get-state >/dev/null 2>&1 || { err "VM not reachable on adb. Boot it and run Connect first."; return 1; }
  printf "  ${C_WARN}?${RESET} Path to Burp CA cert (DER or PEM): "; read -r cert
  [[ -f $cert ]] || { err "file not found"; return 1; }
  local pem="$LAB_DIR/.pme_burp.pem"
  if openssl x509 -inform DER -in "$cert" -out "$pem" 2>/dev/null; then :;
  elif openssl x509 -inform PEM -in "$cert" -out "$pem" 2>/dev/null; then :;
  else err "not a valid certificate"; return 1; fi
  local hash; hash=$(openssl x509 -inform PEM -subject_hash_old -in "$pem" | head -1)
  cp "$pem" "$LAB_DIR/${hash}.0"
  adb -s "$D" root >/dev/null 2>&1; sleep 2; adb connect "$D" >/dev/null 2>&1
  adb -s "$D" remount >/dev/null 2>&1
  if adb -s "$D" push "$LAB_DIR/${hash}.0" /system/etc/security/cacerts/ >/dev/null 2>&1; then
    adb -s "$D" shell chmod 644 /system/etc/security/cacerts/${hash}.0
    ok "Installed system CA (${hash}.0)."
  else err "push failed — is /system read-write? (choose R-W at install)"; return 1; fi
  printf "  ${C_WARN}?${RESET} Burp host IP as seen from VM ${C_MUT}[10.0.2.2]${RESET}: "; read -r bip; bip=${bip:-10.0.2.2}
  printf "  ${C_WARN}?${RESET} Burp port ${C_MUT}[8080]${RESET}: "; read -r bport; bport=${bport:-8080}
  adb -s "$D" shell settings put global http_proxy "${bip}:${bport}"
  ok "Proxy set to ${bip}:${bport}. Reboot the VM (close window + re-run) to finalize the cert."
  warn "Do NOT use 'adb reboot' on Android-x86 — it hangs. Close the QEMU window and relaunch."
}

# --------------------------------------------------------------- doctor/health -
health_check() {
  local D="localhost:5555"
  export PATH="$HOME/.local/bin:$PATH"
  have qemu-system-x86_64 && ok "QEMU installed" || err "QEMU missing"
  ((KVM_RW)) && ok "KVM accessible" || warn "KVM not accessible"
  have adb && ok "adb installed" || err "adb missing"
  if adb connect "$D" >/dev/null 2>&1 && [ "$(adb -s "$D" get-state 2>/dev/null)" = device ]; then
    ok "VM reachable via adb ($D)"
    printf "     root : %s\n" "$(adb -s "$D" shell id 2>/dev/null | tr -d '\r' | cut -d' ' -f1)"
    printf "     proxy: %s\n" "$(adb -s "$D" shell settings get global http_proxy 2>/dev/null | tr -d '\r')"
    ls "$LAB_DIR"/*.qcow2 >/dev/null 2>&1 && ok "disk image present"
    adb -s "$D" shell ls /system/etc/security/cacerts/ 2>/dev/null | grep -q '\.0' && ok "system CA cert(s) present"
    if have frida-ps; then adb -s "$D" forward tcp:27042 tcp:27042 >/dev/null 2>&1
      frida-ps -H localhost:27042 >/dev/null 2>&1 && ok "Frida bridge working (port 27042)" || warn "Frida not responding — run Connect"; fi
  else warn "VM not reachable — boot it (pme-run-*.sh) then Connect."; fi
}

# ------------------------------------------------------------ snapshot manager -
snapshots() {
  local disk; disk=$(ls "$LAB_DIR"/*.qcow2 2>/dev/null | head -1)
  [[ -z $disk ]] && { err "no qcow2 disk found"; return; }
  menu "Snapshot manager ($(basename "$disk")):" "Create 'clean' snapshot" "Restore 'clean' snapshot" "List snapshots" "‹ back"
  case $MENU_CHOICE in
    0) spin "creating snapshot 'clean'" qemu-img snapshot -c clean "$disk" && ok "snapshot 'clean' saved";;
    1) confirm "VM must be OFF. Restore 'clean' now?" && { qemu-img snapshot -a clean "$disk" && ok "restored"; };;
    2) qemu-img snapshot -l "$disk";;
  esac
}

# ------------------------------------------------------------------- config ---
save_config() {
  mkdir -p "$CONFIG_DIR"
  cat >"$CONFIG_FILE" <<EOF
PME_LAB_DIR="$LAB_DIR"
PME_THEME="$THEME"
PME_LAST_KEY="${CHOSEN_KEY:-$REC_KEY}"
PME_VM_RAM="$REC_VM_RAM"
PME_VM_CPU="$REC_VM_CPU"
EOF
  log "config saved"
}
load_config() { [[ -f $CONFIG_FILE ]] && . "$CONFIG_FILE" 2>/dev/null; }

cleanup_lab() {
  warn "This removes generated scripts, ISOs, disks and frida-server from $LAB_DIR."
  confirm "Really wipe the lab? (qcow2 disks included)" || { note "cancelled"; return; }
  rm -f "$LAB_DIR"/pme-*.sh "$LAB_DIR"/*.qcow2 "$LAB_DIR"/*.iso \
        "$LAB_DIR"/frida-server-*-android-x86_64* "$LAB_DIR"/pinning-bypass.js "$LAB_DIR"/.pme_burp.pem "$LAB_DIR"/*.0 2>/dev/null
  ok "lab cleaned."
}

# ---------------------------------------------------------------- theme pick --
pick_theme() {
  menu "Pick a vibe:" "neon (cyan→violet)" "matrix (green rain)" "synthwave (pink→blue)" "‹ back"
  case $MENU_CHOICE in 0) THEME=neon;; 1) THEME=matrix;; 2) THEME=synthwave;; *) return;; esac
  theme_palette; save_config; banner; ok "theme → $THEME"
}

# ------------------------------------------------------------------ full flow -
guided_setup() {
  banner; scan_screen; recommend; rec_screen; pause
  banner; printf "  %s\n\n" "$(grad '━━━  DEPENDENCY DOCTOR  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━')"
  doctor_check; doctor_install; pause
  banner; recommend; rec_screen
  choose_emulator; [[ -z ${CHOSEN_KEY:-} ]] && return
  banner; printf "  %s\n\n" "$(grad '━━━  PROVISIONING  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━')"
  provision_emulator "$CHOSEN_KEY"; echo
  setup_frida; pause
  # offer the unattended installer for supported images
  if [[ $CHOSEN_KEY == ax9 || $CHOSEN_KEY == ax81 ]]; then
    banner; printf "  %s\n" "$(grad '━━━  INSTALL METHOD  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━')"
    menu "How do you want to install Android onto the disk?" \
      "Unattended AUTO-INSTALL  (no menus · /system read-only · Frida for HTTPS)" \
      "Manual installer         (you drive menus · can pick /system read-write)" \
      "Skip for now"
    case $MENU_CHOICE in
      0) banner; auto_install "$CHOSEN_KEY";;
      1) note "Run:  ./pme-install-${CHOSEN_KEY}.sh   then follow the menus.";;
    esac
    pause
  fi
  banner
  printf "  ${C_OK}${BOLD}Setup complete!${RESET}\n\n"
  printf "  Next steps:\n"
  note "1. Boot it:          ./pme-run-${CHOSEN_KEY}.sh"
  note "2. Wire it up:       ./pme-connect.sh"
  note "3. HTTPS intercept:  Frida (any install) OR main menu → 'Burp CA + proxy' (R-W install)"
  note "4. Analyze an APK:   main menu → 'Analyze an APK'  (or  --apk <file>)"
  pause
}

# ------------------------------------------------------- first-run notice ----
first_run_notice() {
  local marker="$CONFIG_DIR/.accepted"
  [[ -f $marker && ${1:-} != force ]] && return 0
  banner
  printf "  %s\n\n" "$(grad '━━━  FIRST-RUN NOTICE  ·  NETWORK & USAGE  ━━━━━━━━━━━━━━')"
  printf "  ${BOLD}This tool builds a local Android lab. Some steps reach the internet —\n  only to fetch packages and images, and always after you confirm.${RESET}\n\n"
  printf "  ${C_ACC}May download from:${RESET}\n"
  printf "    ${C_OK}•${RESET} APT repos ${C_MUT}(your distro)   — qemu, adb, aapt, jadx, apktool… via apt+sudo${RESET}\n"
  printf "    ${C_OK}•${RESET} sourceforge.net           ${C_MUT}— official Android-x86 ISOs${RESET}\n"
  printf "    ${C_OK}•${RESET} github.com/frida/frida    ${C_MUT}— version-matched frida-server${RESET}\n"
  printf "    ${C_OK}•${RESET} PyPI ${C_MUT}(pipx)                — frida-tools${RESET}\n\n"
  printf "  ${C_ACC}100%% offline (never touches the network):${RESET}\n"
  printf "    ${C_MUT}system scan · recommendation · APK static analysis · CA/proxy into your own VM${RESET}\n\n"
  printf "  ${C_WARN}▲ No telemetry. No third-party app backends. Nothing is sent out.${RESET}\n"
  printf "  ${C_WARN}▲ Use only on devices and apps you are authorized to test.${RESET}\n\n"
  if confirm "Understood — continue?"; then
    mkdir -p "$CONFIG_DIR"; : >"$marker"; log "first-run notice accepted"
  else
    clear; printf "\n  ${C_MUT}No problem — nothing was downloaded or changed. Bye.${RESET}\n\n"; exit 0
  fi
}

# ------------------------------------------------------------------ main menu -
main_menu() {
  while true; do
    banner
    printf "  ${C_MUT}lab dir:${RESET} %s   ${C_MUT}theme:${RESET} %s\n" "$LAB_DIR" "$THEME"
    menu "MAIN MENU" \
      "🚀  Guided setup (scan → deps → provision → install → frida)" \
      "🔍  System scan & recommendation" \
      "🩺  Dependency doctor" \
      "📀  Provision an Android image" \
      "⚡  Auto-install Android (unattended)" \
      "🎯  Frida setup (server + unpinning script)" \
      "🔐  Auto-install Burp CA + proxy into VM" \
      "🔬  Analyze an APK (static, local)" \
      "❤️   Health check (verify the whole chain)" \
      "💾  Snapshot manager" \
      "🎨  Change theme" \
      "🧹  Clean up lab" \
      "✖   Quit"
    echo
    case $MENU_CHOICE in
      0) guided_setup;;
      1) banner; scan_screen; recommend; rec_screen; pause;;
      2) banner; printf "  %s\n\n" "$(grad '━━━  DEPENDENCY DOCTOR  ━━━')"; doctor_check; doctor_install; pause;;
      3) banner; scan_specs; recommend; rec_screen; choose_emulator; [[ -n ${CHOSEN_KEY:-} ]] && { provision_emulator "$CHOSEN_KEY"; }; pause;;
      4) banner; printf "  %s\n\n" "$(grad '━━━  UNATTENDED INSTALL  ━━━')"; recommend; choose_emulator; [[ -n ${CHOSEN_KEY:-} ]] && auto_install "$CHOSEN_KEY"; pause;;
      5) banner; printf "  %s\n\n" "$(grad '━━━  FRIDA  ━━━')"; setup_frida; pause;;
      6) banner; printf "  %s\n\n" "$(grad '━━━  BURP CA  ━━━')"; auto_burp; pause;;
      7) banner; printf "  ${C_WARN}?${RESET} Path to APK: "; read -r _apk
         if confirm "Deep decompile with jadx too (slower)?"; then apk_analyze "$_apk" deep; else apk_analyze "$_apk"; fi; pause;;
      8) banner; printf "  %s\n\n" "$(grad '━━━  HEALTH CHECK  ━━━')"; health_check; pause;;
      9) banner; snapshots; pause;;
      10) pick_theme; pause;;
      11) banner; cleanup_lab; pause;;
      12|-1) break;;
    esac
  done
  clear; printf "\n  %s\n\n" "$(grad "  ── stay curious, hack ethically —  ${PME_AUTHOR}  ──")"
}

# ---------------------------------------------------------------------- entry -
main() {
  mkdir -p "$CONFIG_DIR" "$LAB_DIR"
  load_config; theme_palette
  scan_specs
  case "${1:-}" in
    --scan)    scan_screen; recommend; rec_screen; exit 0;;
    --check)   doctor_check; exit 0;;
    --apk)     shift; [[ -n ${1:-} ]] || { echo "usage: --apk <file> [--deep]"; exit 1; }
               recommend; apk_analyze "$1" "$([[ ${2:-} == --deep ]] && echo deep)"; exit $?;;
    --auto-install) shift; [[ -n ${1:-} ]] || { echo "usage: --auto-install <ax9|ax81>"; exit 1; }
               recommend; auto_install "$1"; exit $?;;
    --banner)  banner; exit 0;;
    --notice)  [[ -t 0 && -t 1 ]] && first_run_notice force || cat "$CONFIG_DIR/.accepted" 2>/dev/null; exit 0;;
    --version) echo "Pimp My EmuDroid v$PME_VERSION by $PME_AUTHOR"; exit 0;;
    --help|-h) cat <<H
Pimp My EmuDroid v$PME_VERSION — by $PME_AUTHOR
Usage: $0 [option]
  (no args)              launch the interactive TUI
  --scan                 system scan + emulator recommendation
  --check                dependency doctor (table only)
  --apk <file> [--deep]  static-analyze an APK (--deep adds jadx)
  --auto-install <key>   unattended Android-x86 install (ax9|ax81)
  --notice               re-show the first-run network & usage notice
  --version | --help
H
               exit 0;;
  esac
  # require a real terminal for the TUI
  [[ -t 0 && -t 1 ]] || { echo "Pimp My EmuDroid needs an interactive terminal. Try: --scan / --check"; exit 1; }
  first_run_notice
  main_menu
}
main "$@"
