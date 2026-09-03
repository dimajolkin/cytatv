#!/usr/bin/env bash
# firmware/custom — Android с дампа Cyta, операторский стек выпилен полностью.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CYTA_PART="$ROOT/firmware/cyta/extracted/partitions"
CYTA_FS="$ROOT/firmware/cyta/extracted/filesystems/system"
OUT="$ROOT/firmware/custom"
ASSETS="$OUT/assets"
E2FS="${E2FS:-/opt/homebrew/opt/e2fsprogs/sbin}"
DEBUGFS="${E2FS}/debugfs"
FSCK="${E2FS}/e2fsck"

[[ -x "$DEBUGFS" ]] || { echo "brew install e2fsprogs"; exit 1; }
[[ -f "$CYTA_PART/system.img" ]] || { echo "нет system.img дампа"; exit 1; }
[[ -f "$ASSETS/Lawnchair.apk" ]] || { echo "нет $ASSETS/Lawnchair.apk"; exit 1; }
[[ -f "$ASSETS/Magisk.apk" ]] || { echo "нет $ASSETS/Magisk.apk"; exit 1; }
[[ -f "$ASSETS/magisk-arm/cytasu-daemon" ]] || { echo "нет $ASSETS/magisk-arm/cytasu-daemon — собери cytasu"; exit 1; }
[[ -f "$ASSETS/magisk-arm/su" ]] || { echo "нет $ASSETS/magisk-arm/su (cytasu client)"; exit 1; }
# stock = оригинальный /app/Settings из дампа; custom = q22e settings-ui
SETTINGS_SRC="${SETTINGS_SRC:-stock}"
if [[ "$SETTINGS_SRC" == "custom" ]]; then
  [[ -f "$ASSETS/Settings.apk" ]] || { echo "нет $ASSETS/Settings.apk — собери: (cd ../q22e-android/settings-ui && make apk-for-firmware)"; exit 1; }
fi
[[ -f "$ASSETS/magisk-arm/magisk" ]] || { echo "нет $ASSETS/magisk-arm/* — извлеки из Magisk.apk"; exit 1; }
[[ -f "$ASSETS/dropbear-arm/dropbear" ]] || { echo "нет $ASSETS/dropbear-arm/dropbear"; exit 1; }
[[ -f "$ASSETS/ssh/authorized_keys" ]] || { echo "нет $ASSETS/ssh/authorized_keys"; exit 1; }
BASH_BIN="$ASSETS/bash-arm/bash"
if [[ ! -f "$BASH_BIN" ]]; then
  echo "=== скачать bash (Inknyto/arm-binaries bash.tgz) ==="
  mkdir -p "$ASSETS/bash-arm" "$ASSETS/bash-arm/.dl"
  curl -fsSL "https://raw.githubusercontent.com/Inknyto/arm-binaries/main/bash.tgz" -o "$ASSETS/bash-arm/.dl/bash.tgz"
  tar -xzf "$ASSETS/bash-arm/.dl/bash.tgz" -C "$ASSETS/bash-arm/.dl"
  cp "$ASSETS/bash-arm/.dl/system/xbin/bash" "$BASH_BIN"
  [[ -f "$ASSETS/bash-arm/.dl/system/etc/inputrc" ]] && cp "$ASSETS/bash-arm/.dl/system/etc/inputrc" "$ASSETS/bash-arm/inputrc"
  chmod 755 "$BASH_BIN"
  rm -rf "$ASSETS/bash-arm/.dl"
fi
[[ -f "$BASH_BIN" ]] || { echo "нет $BASH_BIN"; exit 1; }
file "$BASH_BIN" | grep -q 'ARM' || { echo "bash не ARM: $(file "$BASH_BIN")"; exit 1; }
ADBD="$ASSETS/adbd-arm/adbd"
if [[ ! -f "$ADBD" ]]; then
  echo "=== скачать adbd (Inknyto/arm-binaries, static ARM) ==="
  mkdir -p "$ASSETS/adbd-arm"
  curl -fsSL "https://raw.githubusercontent.com/Inknyto/arm-binaries/main/adbd-non-root" -o "$ADBD"
fi
[[ -f "$ADBD" ]] || { echo "нет $ADBD"; exit 1; }
file "$ADBD" | grep -q 'ARM' || { echo "adbd не ARM: $(file "$ADBD")"; exit 1; }
for _apk in TermOnePlus WifiAnalyzer Game2048 Amaze Lightning WifiHub; do
  [[ -f "$ASSETS/extras/${_apk}.apk" ]] || { echo "нет $ASSETS/extras/${_apk}.apk"; exit 1; }
done

mkdir -p "$OUT"
echo "=== copy logo/kernel/system ==="
NEUTRAL_LOGO="$ASSETS/logo/logo-neutral.img"
if [[ -f "$NEUTRAL_LOGO" ]]; then
  cp -f "$NEUTRAL_LOGO" "$OUT/logo.img"
  echo "logo: neutral (чёрный 1080p), не Cyta"
else
  cp -f "$CYTA_PART/logo.img" "$OUT/logo.img"
  echo "logo: fallback Cyta (нет $NEUTRAL_LOGO)"
fi
cp -f "$CYTA_PART/kernel.img" "$OUT/kernel.img"
cp -f "$CYTA_PART/system.img" "$OUT/system.img"
IMG="$OUT/system.img"

echo "=== strip Cyta/operator (full) ==="
python3 - "$IMG" "$CYTA_FS" "$DEBUGFS" <<'PY'
import os, sys, subprocess, tempfile, re

img, fs_root, debugfs = sys.argv[1], sys.argv[2], sys.argv[3]

# Оставить только нужное для железа / UI
KEEP_APP = {
    "BLERemoteControl",   # пульт
    "Bluetooth",
    "Browser2",
    "CertInstaller",
    "DownloadProviderUi",
    "ExtShared",
    "Gallery2",
    "HTMLViewer",
    "HiRMService",        # Hisilicon remote/input
    "HmtBluetooth",
    "HmtCombinedKeyService",
    "HmtNetworkService",  # ethernet mode / backup
    "HmtStatusToast",     # wifi/eth state machine UI
    "HmtStbAPIService",   # часто нужен Settings
    "HmtStbBgService",    # BOOT_COMPLETED → connectDhcp (без него Net мёртв)
    "HmtStbConfigProvider",
    "KeyChain",
    "LatinIME",
    "PacProcessor",
    "PrintSpooler",
    "Settings",           # сток Huawei; custom ставится отдельно если SETTINGS_SRC=custom
    "UserDictionaryProvider",
    "WallpaperBackup",
    "webview",
}

trees = []
# все app/* кроме KEEP
app_dir = os.path.join(fs_root, "app")
for name in sorted(os.listdir(app_dir)):
    if name in KEEP_APP:
        continue
    trees.append(f"app/{name}")

# каталоги/бинарники оператора
trees += [
    "iptv",
    "bin/iptv-setup",
]

# libs IPTV / VR client
lib = os.path.join(fs_root, "lib")
if os.path.isdir(lib):
    for name in os.listdir(lib):
        low = name.lower()
        if "iptv" in low or "vriptv" in low:
            trees.append(f"lib/{name}")

# bootanimation Cyta
if os.path.isfile(os.path.join(fs_root, "media/bootanimation.zip")):
    trees.append("media/bootanimation.zip")

files, dirs = [], []
for tree in trees:
    base = os.path.join(fs_root, tree)
    if not os.path.exists(base):
        print("skip", tree)
        continue
    if os.path.isfile(base):
        files.append(tree)
        continue
    for dirpath, dirnames, filenames in os.walk(base, topdown=False):
        rel = os.path.relpath(dirpath, fs_root).replace("\\", "/")
        for fn in filenames:
            files.append(f"{rel}/{fn}")
        for dn in dirnames:
            dirs.append(f"{rel}/{dn}")
        dirs.append(rel)

seen, cmds = set(), []
for p in files:
    if p not in seen:
        seen.add(p)
        cmds.append(f"rm /{p}")
for p in dirs:
    if p not in seen:
        seen.add(p)
        cmds.append(f"rmdir /{p}")

print(f"remove: {len(trees)} trees → {len(files)} files, {len(dirs)} dirs")
with tempfile.NamedTemporaryFile("w", delete=False) as f:
    f.write("\n".join(cmds) + "\n")
    path = f.name
r = subprocess.run([debugfs, "-w", "-f", path, img], capture_output=True, text=True)
os.unlink(path)
print("debugfs strip code", r.returncode)
PY

WORKDIR=$(mktemp -d)
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

echo "=== patch props / reserveAPP / init ==="
"$DEBUGFS" -R "dump /build.prop $WORKDIR/build.prop" "$IMG" 2>/dev/null
"$DEBUGFS" -R "dump /etc/build_hw.prop $WORKDIR/build_hw.prop" "$IMG" 2>/dev/null || true
"$DEBUGFS" -R "dump /etc/reserveAPP.xml $WORKDIR/reserveAPP.xml" "$IMG" 2>/dev/null || true

python3 - "$WORKDIR" <<'PY'
import os, re, sys
wd = sys.argv[1]

def set_prop(text, key, value):
    pat = re.compile(rf"^{re.escape(key)}=.*$", re.M)
    line = f"{key}={value}"
    if pat.search(text):
        return pat.sub(line, text)
    return text.rstrip() + "\n" + line + "\n"

def del_prop(text, key):
    return re.sub(rf"^{re.escape(key)}=.*\n?", "", text, flags=re.M)

bp = open(f"{wd}/build.prop", encoding="utf-8", errors="replace").read()
# убрать cyta/iptv
for k in [
    "ro.product.bootiptv",
    "persist.sys.iptv.connecthdcp",
    "ro.dolby.iptvcert.enable",
]:
    bp = del_prop(bp, k)

for k, v in [
    ("ro.product.bootiptv", "false"),
    ("persist.sys.iptv.connecthdcp", "false"),
    ("ro.adb.secure", "0"),
    ("persist.sys.usb.config", "none"),
    ("service.adb.tcp.port", "5555"),
    ("persist.adb.tcp.port", "5555"),
    ("persist.service.adb.enable", "1"),
    ("persist.service.consoleenable", "1"),
    # I=тише на UART; краши всегда отдельно (uart-crash + AndroidRuntime stream)
    ("persist.cytatv.uart.loglevel", "I"),
    ("persist.cytatv.uart.shell", "1"),
    ("persist.cytatv.wifi.enable", "1"),
    ("persist.cytatv.sdlinux", "1"),
    ("ro.debuggable", "1"),
    ("ro.secure", "0"),
    ("ro.allow.mock.location", "1"),
    ("ro.custom.cytatv", "cyta-removed"),
    ("ro.build.display.id", "Q22E-custom debloat"),
    # fingerprint без LCYT03/cyta в отображаемой части — оставляем валидный формат
    ("ro.build.version.incremental", "custom-1"),
    # Device Info: Memory/Flash (GetInfoUtil + ro.total.flash fallback)
    ("ro.total.memsize", "2097152"),
    ("ro.total.flash", "8G"),
]:
    bp = set_prop(bp, k, v)

# вычистить cyta из fingerprint строкой
bp = bp.replace("LCYT03.SPC006.B002", "custom")
bp = re.sub(r"cytacyta", "custom", bp, flags=re.I)
open(f"{wd}/build.prop", "w", encoding="utf-8").write(bp)
print("build.prop OK")

hw_path = f"{wd}/build_hw.prop"
if os.path.isfile(hw_path):
    hw = open(hw_path, encoding="utf-8", errors="replace").read()
    hw = del_prop(hw, "ro.product.stb.vmxClientVersion")
    hw = del_prop(hw, "ro.product.stb.vmxTaVersion")
    hw = set_prop(hw, "ro.hw.sys.net.add.iptvroute", "0")
    hw = set_prop(hw, "ro.hw.sys.default.launcher", "ch.deletescape.lawnchair")
    # без HmtProvision — не ждать wizard; сеть поднимает HmtStbBgService
    hw = set_prop(hw, "ro.hw.sys.boot.haswizard", "0")
    # IPTV DHCP opts выкл., но ключи оставляем (стек Huawei их читает)
    hw = set_prop(hw, "ro.hw.sys.net.dhcp.opt60", "0")
    hw = set_prop(hw, "ro.hw.sys.net.dhcp.opt61", "0")
    hw = set_prop(hw, "ro.hw.sys.net.dhcp.opt121", "0")
    open(hw_path, "w", encoding="utf-8").write(hw)
    print("build_hw.prop OK")

# reserveAPP — только системное, без huawei.iptv.*
reserve = """<?xml version="1.0" encoding="UTF-8"?>
<Application>
  <app packageName="system"><persist>true</persist></app>
  <app packageName="system_server"><persist>true</persist></app>
  <app packageName="com.android.systemui"><persist>true</persist></app>
  <app packageName="com.android.settings"><persist>true</persist></app>
  <app packageName="com.android.bluetooth"><persist>true</persist></app>
  <app packageName="com.hisilicon.android.hiRMService"><persist>true</persist></app>
  <app packageName="com.huawei.hmt.hmtNetworkService"><persist>true</persist></app>
  <app packageName="com.huawei.hmt.stbbgservice"><persist>true</persist></app>
  <app packageName="com.huawei.toast"><persist>true</persist></app>
  <app packageName="ch.deletescape.lawnchair"><persist>true</persist></app>
  <app packageName="com.topjohnwu.magisk"><persist>true</persist></app>
</Application>
"""
open(f"{wd}/reserveAPP.xml", "w", encoding="utf-8").write(reserve)
print("reserveAPP.xml OK")
PY

# eng-like props for root/adb
python3 - "$WORKDIR" <<'PY'
import re, sys
wd = sys.argv[1]
def set_prop(text, key, value):
    pat = re.compile(rf"^{re.escape(key)}=.*$", re.M)
    line = f"{key}={value}"
    if pat.search(text):
        return pat.sub(line, text)
    return text.rstrip() + "\n" + line + "\n"
bp = open(f"{wd}/build.prop", encoding="utf-8", errors="replace").read()
for k, v in [
    ("ro.build.type", "userdebug"),
    ("ro.build.tags", "test-keys"),
    ("ro.oem_preferred_pkg", "ch.deletescape.lawnchair"),
]:
    bp = set_prop(bp, k, v)
open(f"{wd}/build.prop", "w", encoding="utf-8").write(bp)
print("build.prop launcher/root OK")
PY

cat > "$WORKDIR/adbd-tcp.sh" <<'SH'
#!/system/bin/sh
# ADB over TCP :5555 — developer mode + права + exec adbd.
T=/dev/ttyAMA0
[ -c "$T" ] || T=/dev/console
ADB=/system/xbin/adbd
PORT=5555

log() { echo "cytatv-adbd: $*" >>"$T" 2>/dev/null; }

log "START uid=$(id) selinux=$(getenforce 2>/dev/null || echo n/a)"

[ -x "$ADB" ] || { log "FAIL no executable $ADB"; exit 1; }
chmod 755 "$ADB" 2>/dev/null
chown root:shell "$ADB" 2>/dev/null

i=0
while [ ! -d /data/local/tmp ] && [ "$i" -lt 60 ]; do
  mkdir -p /data/local/tmp 2>/dev/null
  i=$((i + 1))
  sleep 1
done

# дождаться system_server / settings (иначе put молча no-op)
i=0
while [ "$i" -lt 90 ]; do
  getprop sys.boot_completed 2>/dev/null | grep -q 1 && break
  # settings может ответить раньше boot_completed
  settings get global adb_enabled >/dev/null 2>&1 && break
  i=$((i + 1))
  sleep 2
done

setprop persist.sys.usb.config none
setprop service.adb.tcp.port "$PORT"
setprop persist.adb.tcp.port "$PORT"
setprop persist.service.adb.enable 1

# Режим разработчика + USB debugging (обязательно для TCP adbd)
enable_dev() {
  settings put global development_settings_enabled 1
  settings put global adb_enabled 1
  setprop persist.sys.adb.enable 1
}

enable_dev
sleep 1
DEV=$(settings get global development_settings_enabled 2>/dev/null)
ADB_EN=$(settings get global adb_enabled 2>/dev/null)
# retry до 5 раз
r=0
while [ "$ADB_EN" != "1" ] && [ "$r" -lt 5 ]; do
  log "adb_enabled='$ADB_EN' (want 1) — retry $r"
  enable_dev
  sleep 2
  DEV=$(settings get global development_settings_enabled 2>/dev/null)
  ADB_EN=$(settings get global adb_enabled 2>/dev/null)
  r=$((r + 1))
done

if [ "$ADB_EN" != "1" ]; then
  log "WARN adb_enabled still='$ADB_EN' — пробуем через su settings / content"
  su 0 settings put global adb_enabled 1 2>/dev/null
  su 1000 settings put global adb_enabled 1 2>/dev/null
  ADB_EN=$(settings get global adb_enabled 2>/dev/null)
fi

setprop ctl.stop adbd 2>/dev/null
killall adbd 2>/dev/null
sleep 1

mkdir -p /data/misc/adb 2>/dev/null
chmod 771 /data/misc/adb 2>/dev/null
chown system:shell /data/misc/adb 2>/dev/null
if [ -f /system/etc/adb_keys ]; then
  cp /system/etc/adb_keys /data/misc/adb/adb_keys
  chmod 640 /data/misc/adb/adb_keys
  chown system:shell /data/misc/adb/adb_keys 2>/dev/null
  log "adb_keys installed ($(wc -c </data/misc/adb/adb_keys) bytes)"
else
  log "WARN no /system/etc/adb_keys"
fi

log "CHECK ro.debuggable=$(getprop ro.debuggable) ro.secure=$(getprop ro.secure) ro.adb.secure=$(getprop ro.adb.secure)"
log "CHECK development=$DEV adb_enabled=$ADB_EN tcp=$(getprop service.adb.tcp.port)"
log "CHECK binary=$(ls -lZ "$ADB" 2>/dev/null || ls -l "$ADB")"
log "CHECK /data/misc/adb=$(ls -ldZ /data/misc/adb 2>/dev/null || ls -ld /data/misc/adb)"

if [ "$ADB_EN" != "1" ]; then
  log "FAIL developer/adb not enabled — starting adbd anyway"
fi

log "exec $ADB as $(id) (expect :$PORT)"
exec "$ADB" >>"$T" 2>&1
SH

cat > "$WORKDIR/adbd-watch.sh" <<'SH'
#!/system/bin/sh
T=/dev/ttyAMA0
[ -c "$T" ] || T=/dev/console
log() { echo "cytatv-adbd-watch: $*" >>"$T" 2>/dev/null; }

log "START"
sleep 20

while true; do
  DEV=$(settings get global development_settings_enabled 2>/dev/null)
  ADB_EN=$(settings get global adb_enabled 2>/dev/null)
  if [ "$ADB_EN" != "1" ] || [ "$DEV" != "1" ]; then
    log "re-enable developer (dev=$DEV adb=$ADB_EN)"
    settings put global development_settings_enabled 1 2>/dev/null
    settings put global adb_enabled 1 2>/dev/null
  fi

  setprop service.adb.tcp.port 5555
  setprop persist.adb.tcp.port 5555

  if ! pidof adbd >/dev/null 2>&1; then
    log "adbd dead — restart"
    /system/xbin/adbd-tcp.sh &
    sleep 6
  fi

  LISTEN=0
  grep -q ':15B3 ' /proc/net/tcp 2>/dev/null && LISTEN=1
  grep -q ':15B3 ' /proc/net/tcp6 2>/dev/null && LISTEN=1

  IP=$(ip -4 addr show eth0 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -1)
  [ -z "$IP" ] && IP=$(ip -4 addr show wlan0 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -1)
  [ -z "$IP" ] && IP=$(getprop dhcp.eth0.ipaddress)

  if [ "$LISTEN" = "1" ]; then
    log "OK :5555 pid=$(pidof adbd) dev=$DEV adb=$ADB_EN ip=${IP:-?} → adb connect ${IP:-IP}:5555"
  else
    log "NOT listen :5555 pid=$(pidof adbd) dev=$DEV adb=$ADB_EN ip=${IP:-?} — restart"
    killall adbd 2>/dev/null
    sleep 1
    /system/xbin/adbd-tcp.sh &
  fi

  sleep 20
done
SH

cat > "$WORKDIR/custom_adb.rc" <<'RC'
# ADB TCP :5555 — root, как eng/userdebug adbd
on early-boot
    setprop persist.sys.usb.config none
    setprop service.adb.tcp.port 5555
    setprop persist.adb.tcp.port 5555
    setprop persist.service.adb.enable 1

on property:sys.boot_completed=1
    start cytatv_adbd

service cytatv_adbd /system/xbin/adbd-tcp.sh
    class late_start
    user root
    group root system shell inet misc
    oneshot
    disabled
RC

# Kernel ADVCA — Magisk boot-patch недоступен.
# Root: cytasu-daemon (init, полные capabilities) + /system/xbin/su клиент.
# Magisk оставляем для менеджера/модулей, но su больше не Magisk (Access denied без boot-patch).
cat > "$WORKDIR/custom_root.rc" <<'RC'
on early-init
    write /sys/fs/selinux/enforce 0

on post-fs-data
    mkdir /data/adb 0700 root root
    mkdir /data/adb/magisk 0755 root root
    mkdir /data/local/tmp 0777 root root
    start cytatv_fix_uid
    start cytasu_daemon
    start magisk_daemon

service cytatv_fix_uid /system/xbin/cytatv-fix-uid.sh
    user root
    group root
    oneshot
    disabled

service cytasu_daemon /system/xbin/cytasu-daemon
    user root
    group root

service magisk_daemon /system/xbin/magisk --daemon
    user root
    group root
    oneshot
    disabled

on property:sys.boot_completed=1
    write /sys/fs/selinux/enforce 0
    start cytasu_daemon
    start magisk_daemon
RC

cat > "$WORKDIR/dropbear.sh" <<'SH'
#!/system/bin/sh
export HOME=/data/dropbear
mkdir -p /data/dropbear/.ssh
cp /system/etc/dropbear/authorized_keys /data/dropbear/.ssh/authorized_keys
chmod 700 /data/dropbear /data/dropbear/.ssh
chmod 600 /data/dropbear/.ssh/authorized_keys
cd /data/dropbear || exit 1
# Prefer GNU bash when present (custom image)
if [ -x /system/xbin/bash ]; then
  export SHELL=/system/xbin/bash
elif [ -x /system/bin/bash ]; then
  export SHELL=/system/bin/bash
fi
# -R hostkeys, -B пустой пароль root, ключ: assets/ssh/id_ed25519_q22e
exec /system/xbin/dropbear -R -p 22 -B
SH

cat > "$WORKDIR/custom_ssh.rc" <<'RC'
on post-fs-data
    mkdir /data/dropbear 0700 root root

on boot
    start dropbear

on property:sys.boot_completed=1
    start dropbear

service dropbear /system/xbin/dropbear.sh
    user root
    group root
    oneshot
    disabled

on property:init.svc.dropbear=stopped
    start dropbear
RC

# Kernel уже на console=ttyAMA0; зеркалим Android logcat + отдельно краши.
cat > "$WORKDIR/uart-logcat.sh" <<'SH'
#!/system/bin/sh
T=/dev/ttyAMA0
[ -c "$T" ] || T=/dev/console
LEVEL=$(getprop persist.cytatv.uart.loglevel)
[ -z "$LEVEL" ] && LEVEL=I
{
  echo ""
  echo "=== cytatv uart-logcat *:${LEVEL} + crash/AndroidRuntime -> $T ==="
} >>"$T"

# kmsg уже идёт на console=ttyAMA0 из kernel — не дублируем (забивает UART)

i=0
while [ "$i" -lt 120 ]; do
  getprop init.svc.logd 2>/dev/null | grep -q running && break
  i=$((i + 1))
  sleep 1
done

# Отдельный поток: только краши (не тонут в WiFi/HDMI)
(
  echo "=== cytatv CRASH stream (logcat -b crash + AndroidRuntime) ===" >>"$T"
  /system/bin/logcat -v threadtime -b crash -b main -b system \
    AndroidRuntime:E ActivityManager:I Process:I DEBUG:E FatalAppExit:E Q22eCrash:V '*:S' \
    >>"$T" 2>&1
) &

# Общий поток (по уровню, по умолчанию I — меньше шума)
exec /system/bin/logcat -v threadtime -b all \
  "*:${LEVEL}" AndroidRuntime:E Q22eCrash:V \
  >>"$T" 2>&1
SH

# Tombstones + периодический dump crash-буфера → UART (для native/Java без нашего APK)
cat > "$WORKDIR/uart-crash.sh" <<'SH'
#!/system/bin/sh
T=/dev/ttyAMA0
[ -c "$T" ] || T=/dev/console
DIR=/data/tombstones
MARK=/data/local/tmp/.cytatv-tomb-seen
mkdir -p /data/local/tmp "$DIR" 2>/dev/null
touch "$MARK" 2>/dev/null

log() { echo "cytatv-crash: $*" >>"$T" 2>/dev/null; }

log "START watching $DIR + logcat -b crash"

# стартовый снимок буфера crash
{
  echo ""
  echo "======== cytatv CRASH BUFFER DUMP (boot) ========"
  /system/bin/logcat -d -b crash -v threadtime 2>/dev/null
  echo "======== end crash buffer ========"
} >>"$T" 2>/dev/null

LAST_AM=""
while true; do
  # новые tombstones
  for f in "$DIR"/tombstone_*; do
    [ -f "$f" ] || continue
    grep -qxF "$f" "$MARK" 2>/dev/null && continue
    echo "$f" >>"$MARK"
    {
      echo ""
      echo "======== TOMBSTONE $f ========"
      head -c 65536 "$f" 2>/dev/null
      echo ""
      echo "======== end tombstone ========"
    } >>"$T" 2>/dev/null
    log "dumped $f"
  done

  # ActivityManager: Process ... has died / Force finishing
  LINE=$(/system/bin/logcat -d -b main -b system -v brief \
    ActivityManager:I AndroidRuntime:E '*:S' 2>/dev/null | tail -1)
  if [ -n "$LINE" ] && [ "$LINE" != "$LAST_AM" ]; then
    echo "$LINE" | grep -qiE 'died|FATAL|Force finishing|crash|ANR' && {
      LAST_AM="$LINE"
      {
        echo ""
        echo "======== cytatv PROCESS DIE / FATAL ========"
        echo "$LINE"
        /system/bin/logcat -d -b crash -b main -v threadtime \
          AndroidRuntime:E ActivityManager:I DEBUG:E '*:S' 2>/dev/null | tail -80
        echo "======== end ========"
      } >>"$T" 2>/dev/null
    }
  fi

  sleep 2
done
SH

cat > "$WORKDIR/uart-shell.sh" <<'SH'
#!/system/bin/sh
# Эксперимент: чтение команд с UART RX (на Q22E железо может не принимать).
T=/dev/ttyAMA0
[ -c "$T" ] || exit 0
case "$(getprop persist.cytatv.uart.shell)" in
  0|false|no) exit 0 ;;
esac
BB=/system/xbin/busybox
STTY=stty
[ -x "$BB" ] && STTY="$BB stty"
$STTY -F "$T" 115200 cs8 -cstopb -parenb raw -echo 2>/dev/null || true
{
  echo ""
  echo "=== cytatv uart-shell (RX) — Enter=run, help, exit ==="
  echo "# "
} >>"$T"
while true; do
  IFS= read -r line <"$T" 2>/dev/null || { sleep 2; continue; }
  line=$(printf '%s' "$line" | tr -d '\r\n')
  [ -z "$line" ] && { printf '# ' >>"$T"; continue; }
  case "$line" in
    exit|quit) echo "bye" >>"$T"; break ;;
    help)
      cat >>"$T" <<'EOF'
# cmds: id, getprop, ip addr, ifconfig eth0, reboot, setprop ...
EOF
      ;;
    reboot) reboot ;;
    *)
      echo "# $line" >>"$T"
      sh -c "$line" >>"$T" 2>&1
      ;;
  esac
  printf '# ' >>"$T"
done
SH

# MT7662T: kernel loader ищет patch в /lib/firmware (в /etc/firmware есть, в lib — нет).
cat > "$WORKDIR/wifi-boot.sh" <<'SH'
#!/system/bin/sh
T=/dev/ttyAMA0
[ -c "$T" ] || T=/dev/console
log() { echo "wifi-boot: $*" >>"$T" 2>/dev/null; }

case "$(getprop persist.cytatv.wifi.enable)" in
  0|false|no) exit 0 ;;
esac

mkdir -p /data/wifi/cal
if [ ! -f /data/wifi/cal/wlan_eeprom.bin ] && [ -f /system/etc/wifi/cal/wlan_eeprom.bin ]; then
  cp /system/etc/wifi/cal/wlan_eeprom.bin /data/wifi/cal/
  [ -f /system/etc/wifi/cal/binsha256 ] && cp /system/etc/wifi/cal/binsha256 /data/wifi/cal/
  chmod 644 /data/wifi/cal/wlan_eeprom.bin 2>/dev/null
  log "cal → /data/wifi/cal"
fi
[ -x /system/bin/recoverywifi ] && /system/bin/recoverywifi

(
  i=0
  while [ "$i" -lt 120 ]; do
    getprop sys.boot_completed 2>/dev/null | grep -q 1 && break
    i=$((i + 1))
    sleep 2
  done
  sleep 5
  settings put global wifi_on 1 2>/dev/null
  svc wifi enable 2>/dev/null
  service call wifi 13 i32 1 2>/dev/null
  sleep 3
  if ip link show wlan0 2>/dev/null | grep -q wlan0; then
    log "wlan0 up"
  else
    log "wlan0 missing — driver not loaded (enable WiFi in Settings?)"
  fi
) &
SH

cat > "$WORKDIR/cytatv-sd-linux.sh" <<'SH'
#!/system/bin/sh
# Mount e2d rootfs (microSD or USB) → Debian chroot as root: SSH :22 + Enigma2 UI.
T=/dev/ttyAMA0
[ -c "$T" ] || T=/dev/console
log() { echo "cytatv: sd-linux $*" >>"$T" 2>/dev/null; }

case "$(getprop persist.cytatv.sdlinux)" in
  0|false|no) log "skip (persist.cytatv.sdlinux=0)"; exit 0 ;;
esac

MNT=/mnt/linux
LOCK=/data/local/tmp/cytatv-sd-linux.lock
mkdir -p /data/local/tmp 2>/dev/null
if [ -f "$LOCK" ]; then
  old=$(cat "$LOCK" 2>/dev/null)
  [ -n "$old" ] && kill -0 "$old" 2>/dev/null && { log "already running pid=$old"; exit 0; }
fi
echo $$ >"$LOCK"

# Try mount candidate; echo path only if /etc/debian_version appears.
try_debian() {
  cand="$1"
  kind="$2"
  [ -b "$cand" ] || return 1
  mkdir -p "$MNT"
  if grep -q " $MNT " /proc/mounts 2>/dev/null; then
    [ -f "$MNT/etc/debian_version" ] || { umount "$MNT" 2>/dev/null || true; return 1; }
    echo "$cand $kind"
    return 0
  fi
  if mount -t ext4 -o rw,noatime "$cand" "$MNT" 2>/dev/null \
    || mount -o rw,noatime "$cand" "$MNT" 2>/dev/null; then
    if [ -f "$MNT/etc/debian_version" ]; then
      echo "$cand $kind"
      return 0
    fi
    umount "$MNT" 2>/dev/null || true
  fi
  return 1
}

find_debian() {
  for c in \
    /dev/block/mmcblk1p1 /dev/block/mmcblk1 \
    /dev/mmcblk1p1 /dev/mmcblk1 \
    /dev/block/vold/public:179,1 /dev/block/vold/179:1
  do
    try_debian "$c" sd && return 0
  done
  for c in \
    /dev/block/sda1 /dev/block/sda /dev/sda1 /dev/sda \
    /dev/block/sdb1 /dev/block/sdb /dev/sdb1 /dev/sdb
  do
    try_debian "$c" usb && return 0
  done
  for c in /dev/block/platform/*/by-name/* /dev/block/sd[a-z] /dev/block/sd[a-z][0-9] \
           /dev/block/mmcblk1 /dev/block/mmcblk1p1; do
    case "$c" in
      *mmcblk1*) try_debian "$c" sd && return 0 ;;
      *sd[a-z]*) try_debian "$c" usb && return 0 ;;
    esac
  done
  return 1
}

FOUND=""
i=0
while [ "$i" -lt 60 ]; do
  FOUND=$(find_debian) && break
  i=$((i + 1))
  sleep 1
done

if [ -z "$FOUND" ]; then
  log "skip (no sd/usb debian)"
  rm -f "$LOCK"
  exit 0
fi
set -- $FOUND
PART="$1"
KIND="$2"
log "device $PART ($KIND)"

for d in proc sys dev dev/pts run tmp; do
  mkdir -p "$MNT/$d"
done
grep -q " $MNT/proc " /proc/mounts || mount -t proc proc "$MNT/proc"
grep -q " $MNT/sys " /proc/mounts || mount -t sysfs sysfs "$MNT/sys"
grep -q " $MNT/dev " /proc/mounts || mount -o bind /dev "$MNT/dev"
grep -q " $MNT/dev/pts " /proc/mounts || mount -t devpts devpts "$MNT/dev/pts" 2>/dev/null || true
grep -q " $MNT/run " /proc/mounts || mount -t tmpfs tmpfs "$MNT/run" 2>/dev/null || true
grep -q " $MNT/tmp " /proc/mounts || mount -t tmpfs tmpfs "$MNT/tmp" 2>/dev/null || true

# DNS from Android
if [ -f /system/etc/resolv.conf ]; then
  cp /system/etc/resolv.conf "$MNT/etc/resolv.conf" 2>/dev/null || true
elif [ -f /etc/resolv.conf ]; then
  cp /etc/resolv.conf "$MNT/etc/resolv.conf" 2>/dev/null || true
else
  printf 'nameserver 8.8.8.8\nnameserver 1.1.1.1\n' >"$MNT/etc/resolv.conf" 2>/dev/null || true
fi

# Same SSH key as Android custom (root login)
mkdir -p "$MNT/root/.ssh" "$MNT/etc/dropbear" 2>/dev/null
if [ -f /system/etc/dropbear/authorized_keys ]; then
  cp /system/etc/dropbear/authorized_keys "$MNT/root/.ssh/authorized_keys" 2>/dev/null || true
  cp /system/etc/dropbear/authorized_keys "$MNT/etc/dropbear/authorized_keys" 2>/dev/null || true
  chmod 700 "$MNT/root/.ssh" 2>/dev/null || true
  chmod 600 "$MNT/root/.ssh/authorized_keys" 2>/dev/null || true
fi

log "started (chroot $MNT root)"

# Free :22 — Android dropbear → Debian ssh as root
stop_android_ssh() {
  setprop ctl.stop dropbear 2>/dev/null || true
  setprop ctl.stop dropbeard 2>/dev/null || true
  killall dropbear 2>/dev/null || true
  killall dropbearmulti 2>/dev/null || true
}
stop_android_ssh

(
  sleep 1
  stop_android_ssh
  if [ -x "$MNT/usr/sbin/sshd" ]; then
    mkdir -p "$MNT/var/run/sshd" 2>/dev/null
    chroot "$MNT" /usr/sbin/sshd 2>>"$T" && log "sshd ok :22 (root)"
  elif [ -x "$MNT/sbin/dropbear" ]; then
    chroot "$MNT" /sbin/dropbear -R -p 22 2>>"$T" && log "dropbear ok :22 (root)"
  elif [ -x "$MNT/usr/sbin/dropbear" ]; then
    chroot "$MNT" /usr/sbin/dropbear -R -p 22 2>>"$T" && log "dropbear ok :22 (root)"
  else
    log "ssh fail (no sshd/dropbear in debian)"
  fi
) &

# HDMI: stop Android UI, start Enigma2 as root
(
  sleep 3
  log "ui handoff: stop zygote/surfaceflinger"
  setprop ctl.stop zygote 2>/dev/null || true
  setprop ctl.stop zygote_secondary 2>/dev/null || true
  setprop ctl.stop surfaceflinger 2>/dev/null || true
  sleep 2
  killall system_server 2>/dev/null || true
  killall surfaceflinger 2>/dev/null || true

  # init service already uid 0 — keep root env inside chroot
  ok=0
  if [ -x "$MNT/etc/init.d/enigma2" ]; then
    chroot "$MNT" /bin/sh -c 'export HOME=/root USER=root LOGNAME=root; exec /etc/init.d/enigma2 start' 2>>"$T" && ok=1
  fi
  if [ "$ok" = 0 ] && [ -x "$MNT/usr/bin/enigma2" ]; then
    chroot "$MNT" /bin/sh -c 'export HOME=/root USER=root LOGNAME=root; exec /usr/bin/enigma2' 2>>"$T" &
    ok=1
  fi
  if [ "$ok" = 0 ] && [ -x "$MNT/usr/local/bin/enigma2" ]; then
    chroot "$MNT" /bin/sh -c 'export HOME=/root USER=root LOGNAME=root; exec /usr/local/bin/enigma2' 2>>"$T" &
    ok=1
  fi
  if [ "$ok" = 1 ]; then
    log "enigma2 ok (uid0 root)"
  else
    log "enigma2 fail (no binary/init)"
  fi
) &

# UART root shell (backup)
(
  sleep 5
  if [ -x "$MNT/sbin/getty" ] || [ -x "$MNT/sbin/agetty" ]; then
    GETTY=/sbin/agetty
    [ -x "$MNT/sbin/agetty" ] || GETTY=/sbin/getty
    chroot "$MNT" "$GETTY" -a root -L ttyAMA0 115200 vt100 2>>"$T"
  elif [ -x "$MNT/bin/bash" ]; then
    {
      echo ""
      echo "=== Debian chroot root ==="
    } >>"$T"
    chroot "$MNT" /bin/bash -l </dev/ttyAMA0 >>"$T" 2>&1
  fi
) &

exit 0
SH

cat > "$WORKDIR/custom_sdlinux.rc" <<'RC'
on property:sys.boot_completed=1
    start cytatv_sd_linux

service cytatv_sd_linux /system/xbin/cytatv-sd-linux.sh
    class late_start
    user root
    group root
    oneshot
    disabled
RC

cat > "$WORKDIR/cytatv-fix-uid.sh" <<'SH'
#!/system/bin/sh
# Если Settings не uid 1000: снести packages.xml один раз, чтобы PM пересканировал
# priv-app с sharedUserId (мок подписи в services.jar).
T=/dev/ttyAMA0
[ -c "$T" ] || T=/dev/console
PKG=com.android.settings
PKG_XML=/data/system/packages.xml
FLAG=/data/local/tmp/.cytatv-uid-wiped

log() { echo "cytatv-fix-uid: $*" >>"$T" 2>/dev/null; }

log "START xml=$PKG_XML wiped=$( [ -f "$FLAG" ] && echo yes || echo no )"

i=0
while [ ! -f "$PKG_XML" ] && [ "$i" -lt 8 ]; do
  log "wait packages.xml ($i)"
  sleep 1
  i=$((i + 1))
done

if [ ! -f "$PKG_XML" ]; then
  log "no packages.xml yet (first scan)"
  exit 0
fi

ENTRY=$(grep "name=\"$PKG\"" "$PKG_XML" 2>/dev/null | head -1)
log "entry: $ENTRY"

if [ -z "$ENTRY" ]; then
  log "package not registered yet"
  exit 0
fi

echo "$ENTRY" | grep -q 'userId="1000"' && echo "$ENTRY" | grep -q 'sharedUserId="android.uid.system"' && {
  log "OK already uid=1000 sharedUser"
  exit 0
}

if [ -f "$FLAG" ]; then
  log "FAIL already wiped once, still not uid 1000"
  exit 1
fi

log "WIPING packages.xml (+ backup/list) so PM rescan with mocked signatures"
mkdir -p /data/local/tmp 2>/dev/null
cp "$PKG_XML" /data/local/tmp/packages.xml.bak.cytatv 2>/dev/null
touch "$FLAG"
rm -f "$PKG_XML" /data/system/packages-backup.xml /data/system/packages.xml.bak \
      /data/system/packages.list /data/system/packages-stopped.xml 2>/dev/null
sync
log "wiped — caller should reboot"
exit 4
SH

cat > "$WORKDIR/cytatv-boot.sh" <<'SH'
#!/system/bin/sh
T=/dev/ttyAMA0
[ -c "$T" ] || T=/dev/console
echo "=== cytatv-boot.sh ===" >>"$T" 2>/dev/null

echo 0 > /sys/fs/selinux/enforce 2>/dev/null

# uid-patch: не блокируем boot, если packages.xml ещё нет (first boot)
[ -x /system/xbin/cytatv-fix-uid.sh ] && /system/xbin/cytatv-fix-uid.sh
echo "cytatv: fix-uid exit=$?" >>"$T" 2>/dev/null

# --- root check (Magisk /system/xbin/su) ---
(
  sleep 8
  echo "=== cytatv root-check ===" >>"$T" 2>/dev/null
  SU=/system/xbin/su
  [ -x "$SU" ] || SU=/system/bin/su
  if [ ! -x "$SU" ] && [ ! -x /system/xbin/magisk ]; then
    echo "cytatv: root FAIL (no su/magisk)" >>"$T" 2>/dev/null
    exit 0
  fi
  [ -x /system/xbin/magisk ] && /system/xbin/magisk --daemon >/dev/null 2>&1
  ID0=$("$SU" 0 -c id 2>/dev/null)
  ID1=$("$SU" 1000 -c id 2>/dev/null)
  echo "cytatv: su0=$ID0" >>"$T" 2>/dev/null
  echo "cytatv: su1000=$ID1" >>"$T" 2>/dev/null
  echo "$ID0" | grep -q 'uid=0' && echo "cytatv: root OK (uid 0)" >>"$T" 2>/dev/null \
    || echo "cytatv: root FAIL (su 0)" >>"$T" 2>/dev/null
  echo "$ID1" | grep -q 'uid=1000' && echo "cytatv: system OK (uid 1000)" >>"$T" 2>/dev/null \
    || echo "cytatv: system FAIL (su 1000)" >>"$T" 2>/dev/null
) &

[ -x /system/xbin/uart-logcat.sh ] && /system/xbin/uart-logcat.sh &
[ -x /system/xbin/uart-crash.sh ] && /system/xbin/uart-crash.sh &
[ -x /system/xbin/uart-shell.sh ] && /system/xbin/uart-shell.sh &

[ -x /system/xbin/adbd-tcp.sh ] && /system/xbin/adbd-tcp.sh &
[ -x /system/xbin/adbd-watch.sh ] && /system/xbin/adbd-watch.sh &
(
  i=0
  while [ "$i" -lt 30 ]; do
    pidof adbd >/dev/null 2>&1 && grep -q ':15B3 ' /proc/net/tcp 2>/dev/null && break
    i=$((i + 1))
    sleep 5
  done
  echo "cytatv: adbd after boot pid=$(pidof adbd) listen5555=$(grep -c ':15B3 ' /proc/net/tcp /proc/net/tcp6 2>/dev/null | tr '\n' '+')" >>"$T" 2>/dev/null
) &

(
  mkdir -p /data/adb/magisk 2>/dev/null
  [ -x /system/xbin/magisk ] && /system/xbin/magisk --daemon &
) &

(
  i=0
  while [ "$i" -lt 90 ]; do
    [ -d /data ] && break
    i=$((i + 1))
    sleep 2
  done
  [ -x /system/xbin/dropbear.sh ] && /system/xbin/dropbear.sh &
) &

[ -x /system/xbin/wifi-boot.sh ] && /system/xbin/wifi-boot.sh &

(
  i=0
  while [ "$i" -lt 90 ]; do
    getprop sys.boot_completed 2>/dev/null | grep -q 1 && break
    i=$((i + 1))
    sleep 2
  done
  sleep 3
  PKG=com.android.settings
  XML=/data/system/packages.xml
  REBOOT_FLAG=/data/local/tmp/.cytatv-uid-reboot
  FAIL_FLAG=/data/local/tmp/.cytatv-uid-FAIL

  XML_LINE=$(grep "name=\"$PKG\"" "$XML" 2>/dev/null | head -1)
  echo "cytatv: packages.xml: $XML_LINE" >>"$T" 2>/dev/null

  UID_S=$(dumpsys package "$PKG" 2>/dev/null | grep -m1 'userId=' | sed 's/.*userId=\([0-9]*\).*/\1/')
  SHARED=$(dumpsys package "$PKG" 2>/dev/null | grep -m1 'sharedUser=' )
  echo "cytatv: dumpsys $PKG userId=$UID_S $SHARED" >>"$T" 2>/dev/null

  if [ "$UID_S" != "1000" ]; then
    echo "cytatv: UID FAIL want=1000 got=${UID_S:-none}" >>"$T" 2>/dev/null
    [ -x /system/xbin/cytatv-fix-uid.sh ] && /system/xbin/cytatv-fix-uid.sh
    echo "cytatv: fix-uid retry exit=$?" >>"$T" 2>/dev/null

    if [ ! -f "$REBOOT_FLAG" ]; then
      echo patched-reboot >"$REBOOT_FLAG"
      echo "cytatv: UID not 1000 — wipe packages.xml + REBOOT once" >>"$T" 2>/dev/null
      sleep 2
      reboot
      exit 0
    fi

    echo "cytatv: ========================================" >>"$T" 2>/dev/null
    echo "cytatv: FATAL Settings uid=${UID_S:-none} (need 1000)" >>"$T" 2>/dev/null
    echo "cytatv: xml=$XML_LINE" >>"$T" 2>/dev/null
    echo "cytatv: STOP zygote (boot broken on purpose)" >>"$T" 2>/dev/null
    echo "cytatv: ========================================" >>"$T" 2>/dev/null
    echo "uid=$UID_S xml=$XML_LINE" >"$FAIL_FLAG"
    setprop cytatv.settings.uid_ok 0
    sleep 1
    stop zygote
    stop
    exit 1
  fi

  echo "cytatv: Settings UID OK (1000)" >>"$T" 2>/dev/null
  setprop cytatv.settings.uid_ok 1
  rm -f "$FAIL_FLAG" "$REBOOT_FLAG" 2>/dev/null

  for P in \
    android.permission.ACCESS_FINE_LOCATION \
    android.permission.ACCESS_COARSE_LOCATION \
    android.permission.WRITE_SECURE_SETTINGS \
    android.permission.WRITE_SETTINGS \
    android.permission.CHANGE_WIFI_STATE \
    android.permission.ACCESS_WIFI_STATE \
    android.permission.ACCESS_NETWORK_STATE \
    android.permission.INTERNET
  do
    pm grant "$PKG" "$P" >/dev/null 2>&1
  done
  echo "cytatv: pm grant $PKG done" >>"$T" 2>/dev/null

  SU=/system/xbin/su
  [ -x "$SU" ] || SU=/system/bin/su
  if [ -x /system/xbin/magisk ] || [ -x "$SU" ]; then
    /system/xbin/magisk --sqlite \
      "REPLACE INTO policies (uid,policy,until,logging,notification) VALUES(1000,2,0,1,0)" \
      >/dev/null 2>&1
    echo "cytatv: magisk allow uid=1000 ($PKG)" >>"$T" 2>/dev/null
  fi
  [ -x /system/xbin/cytatv-sd-linux.sh ] && /system/xbin/cytatv-sd-linux.sh
) &
SH

cat > "$WORKDIR/custom_uart.rc" <<'RC'
on early-boot
    write /proc/sys/kernel/printk "7 4 1 7"

on property:init.svc.logd=running
    start uart_logcat
    start uart_crash

on property:sys.boot_completed=1
    start uart_logcat
    start uart_crash

service uart_logcat /system/xbin/uart-logcat.sh
    user root
    group root system log
    oneshot
    disabled

service uart_crash /system/xbin/uart-crash.sh
    user root
    group root system log
    oneshot
    disabled

on property:init.svc.uart_logcat=stopped
    start uart_logcat

on property:init.svc.uart_crash=stopped
    start uart_crash
RC

write_back() {
  local host="$1" guest="$2"
  "$DEBUGFS" -w -R "rm $guest" "$IMG" 2>/dev/null || true
  "$DEBUGFS" -w -R "write $host $guest" "$IMG" 2>/dev/null
  # mode: APK 0644, binaries 0755
  local mode="${3:-}"
  if [[ -n "$mode" ]]; then
    "$DEBUGFS" -w -R "set_inode_field $guest mode $mode" "$IMG" 2>/dev/null || true
  fi
}

write_back "$WORKDIR/build.prop" /build.prop
[[ -f "$WORKDIR/build_hw.prop" ]] && write_back "$WORKDIR/build_hw.prop" /etc/build_hw.prop
write_back "$WORKDIR/reserveAPP.xml" /etc/reserveAPP.xml
"$DEBUGFS" -w -R "mkdir /etc/init" "$IMG" 2>/dev/null || true
write_back "$WORKDIR/custom_adb.rc" /etc/init/custom_adb.rc
write_back "$WORKDIR/custom_root.rc" /etc/init/custom_root.rc
write_back "$WORKDIR/custom_ssh.rc" /etc/init/custom_ssh.rc
write_back "$WORKDIR/custom_uart.rc" /etc/init/custom_uart.rc
write_back "$WORKDIR/custom_sdlinux.rc" /etc/init/custom_sdlinux.rc
"$DEBUGFS" -w -R "mkdir /xbin" "$IMG" 2>/dev/null || true
"$DEBUGFS" -w -R "mkdir /mnt" "$IMG" 2>/dev/null || true
"$DEBUGFS" -w -R "mkdir /mnt/linux" "$IMG" 2>/dev/null || true
write_back "$WORKDIR/uart-logcat.sh" /xbin/uart-logcat.sh 0100755
write_back "$WORKDIR/uart-crash.sh" /xbin/uart-crash.sh 0100755
write_back "$WORKDIR/uart-shell.sh" /xbin/uart-shell.sh 0100755
write_back "$WORKDIR/wifi-boot.sh" /xbin/wifi-boot.sh 0100755
write_back "$WORKDIR/adbd-tcp.sh" /xbin/adbd-tcp.sh 0100755
write_back "$WORKDIR/adbd-watch.sh" /xbin/adbd-watch.sh 0100755
write_back "$WORKDIR/cytatv-sd-linux.sh" /xbin/cytatv-sd-linux.sh 0100755
write_back "$ADBD" /xbin/adbd 0100755
if [[ -f "$ASSETS/adb/adb_keys" ]]; then
  write_back "$ASSETS/adb/adb_keys" /etc/adb_keys 0100644
  echo "=== adb_keys → /etc/adb_keys (host pubkey) ==="
fi
write_back "$WORKDIR/cytatv-fix-uid.sh" /xbin/cytatv-fix-uid.sh 0100755
write_back "$WORKDIR/cytatv-boot.sh" /xbin/cytatv-boot.sh 0100755

# Android 7 (Huawei bigfish): /etc/init/custom_*.rc может не подхватиться init.
# init.bigfish.sh вызывается из ramdisk init.rc — надёжный хук.
echo "=== patch init.bigfish.sh (cytatv-boot) ==="
"$DEBUGFS" -R "dump /etc/init.bigfish.sh $WORKDIR/init.bigfish.sh" "$IMG" 2>/dev/null
if [[ -f "$WORKDIR/init.bigfish.sh" ]]; then
  python3 - "$WORKDIR/init.bigfish.sh" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path, encoding="utf-8", errors="replace").read()
text = re.sub(r'\n# cytatv[^\n]*\n(?:.*\n)*?(?=\n[^#\s]|\Z)', '\n', text, flags=re.M)
text = re.sub(r'\n\[ -x /system/xbin/uart-logcat\.sh \].*\n', '\n', text)
text = re.sub(r'\n\[ -x /system/xbin/cytatv-fix-uid\.sh \].*\n', '\n', text)
text = re.sub(r'\n\[ -x /system/xbin/cytatv-boot\.sh \].*\n', '\n', text)
early = (
    '\n# cytatv early marker\n'
    'echo "=== cytatv init.bigfish.sh ===" > /dev/ttyAMA0 2>/dev/null || '
    'echo "=== cytatv init.bigfish.sh ===" > /dev/console\n'
)
hook = (
    '\n# cytatv boot: uid-patch (sync, до PM), затем остальное в фоне\n'
    '[ -x /system/xbin/cytatv-fix-uid.sh ] && /system/xbin/cytatv-fix-uid.sh\n'
    '[ -x /system/xbin/cytatv-boot.sh ] && /system/xbin/cytatv-boot.sh &\n'
)
lines = text.splitlines(keepends=True)
out, inserted = [], False
for line in lines:
    if line.startswith("#!/"):
        out.append(line)
        if early.strip() not in text:
            out.append(early)
        inserted = True
        continue
    out.append(line)
if not inserted:
    out.insert(0, "#!/system/bin/sh\n" + early)
if hook.strip() not in text:
    out.append(hook)
open(path, "w", encoding="utf-8").write("".join(out))
print("init.bigfish.sh: cytatv-boot hook")
PY
  write_back "$WORKDIR/init.bigfish.sh" /etc/init.bigfish.sh 0100755
else
  echo "WARN: нет /etc/init.bigfish.sh"
fi

# Дублируем сервис в logd.rc — тот же каталог, что и logd.
"$DEBUGFS" -R "dump /etc/init/logd.rc $WORKDIR/logd.rc" "$IMG" 2>/dev/null
if [[ -f "$WORKDIR/logd.rc" ]] && ! grep -q 'uart_crash' "$WORKDIR/logd.rc"; then
  # убрать старый только-uart_logcat блок если был
  if ! grep -q 'uart_logcat' "$WORKDIR/logd.rc"; then
    :
  fi
  cat >> "$WORKDIR/logd.rc" <<'RC'

# cytatv: logcat + crashes → ttyAMA0
on property:init.svc.logd=running
    start uart_logcat
    start uart_crash

service uart_logcat /system/xbin/uart-logcat.sh
    user root
    group root system log
    oneshot
    disabled

service uart_crash /system/xbin/uart-crash.sh
    user root
    group root system log
    oneshot
    disabled

on property:init.svc.uart_logcat=stopped
    start uart_logcat

on property:init.svc.uart_crash=stopped
    start uart_crash
RC
  write_back "$WORKDIR/logd.rc" /etc/init/logd.rc
  echo "logd.rc: uart_logcat + uart_crash appended"
fi

# WiFi cal живёт в userdata — после wipe Net/WiFi без EEPROM не поднимается.
# Кладём копию в system и указываем путь в wifi_cal.conf.
WIFI_CAL_SRC="$ROOT/firmware/cyta/extracted/filesystems/userdata/wifi/cal/wlan_eeprom.bin"
WIFI_CAL_HASH="$ROOT/firmware/cyta/extracted/filesystems/userdata/wifi/cal/binsha256"
if [[ -f "$WIFI_CAL_SRC" ]]; then
  echo "=== wifi cal → /etc/wifi/cal (survive userdata wipe) ==="
  "$DEBUGFS" -R "dump /etc/wifi/wifi_cal.conf $WORKDIR/wifi_cal.conf" "$IMG" 2>/dev/null
  if [[ -f "$WORKDIR/wifi_cal.conf" ]]; then
    sed -i.bak 's|^CUST_EEPROMLoadPath=.*|CUST_EEPROMLoadPath=/system/etc/wifi/cal/wlan_eeprom.bin|' \
      "$WORKDIR/wifi_cal.conf"
    write_back "$WORKDIR/wifi_cal.conf" /etc/wifi/wifi_cal.conf
  fi
  "$DEBUGFS" -w -R "mkdir /etc/wifi/cal" "$IMG" 2>/dev/null || true
  write_back "$WIFI_CAL_SRC" /etc/wifi/cal/wlan_eeprom.bin 0100644
  [[ -f "$WIFI_CAL_HASH" ]] && write_back "$WIFI_CAL_HASH" /etc/wifi/cal/binsha256 0100600
else
  echo "WARN: нет $WIFI_CAL_SRC — WiFi после wipe userdata может не подняться"
fi

# mt7662t_* только в /etc/firmware — продублировать в /lib/firmware для kernel firmware loader
echo "=== WiFi firmware → /lib/firmware ==="
for _fw in mt7662t_patch_e1_hdr.bin mt7662t_firmware_e1.bin; do
  _src="/etc/firmware/$_fw"
  _dst="/lib/firmware/$_fw"
  if "$DEBUGFS" -R "stat $_src" "$IMG" >/dev/null 2>&1; then
    "$DEBUGFS" -w -R "rm $_dst" "$IMG" 2>/dev/null || true
    WORK_FW=$(mktemp)
    "$DEBUGFS" -R "dump $_src $WORK_FW" "$IMG" 2>/dev/null
    write_back "$WORK_FW" "$_dst" 0100644
    rm -f "$WORK_FW"
    echo "  $_fw → lib/firmware"
  fi
done

echo "=== Lawnchair + Magisk (priv-app) + cytasu su + dropbear ==="
"$DEBUGFS" -w -R "rm -r /priv-app/OpenLauncher" "$IMG" 2>/dev/null || true
"$DEBUGFS" -w -R "rm /priv-app/OpenLauncher/OpenLauncher.apk" "$IMG" 2>/dev/null || true
"$DEBUGFS" -w -R "mkdir /priv-app/Lawnchair" "$IMG" 2>/dev/null || true
"$DEBUGFS" -w -R "mkdir /priv-app/Magisk" "$IMG" 2>/dev/null || true
write_back "$ASSETS/Lawnchair.apk" /priv-app/Lawnchair/Lawnchair.apk 0100644
write_back "$ASSETS/Magisk.apk" /priv-app/Magisk/Magisk.apk 0100644

if [[ "$SETTINGS_SRC" == "custom" ]]; then
  echo "=== install /priv-app/Settings (Q22E custom, stock /app/Settings removed) ==="
  "$DEBUGFS" -w -R "rm /priv-app/Settings/Settings.apk" "$IMG" 2>/dev/null || true
  "$DEBUGFS" -w -R "rmdir /priv-app/Settings" "$IMG" 2>/dev/null || true
  "$DEBUGFS" -w -R "mkdir /priv-app/Settings" "$IMG" 2>/dev/null || true
  "$DEBUGFS" -w -R "rm /app/Settings/Settings.apk" "$IMG" 2>/dev/null || true
  for _o in arm arm64; do
    "$DEBUGFS" -w -R "rm /app/Settings/oat/$_o/Settings.odex" "$IMG" 2>/dev/null || true
    "$DEBUGFS" -w -R "rm /app/Settings/oat/$_o/Settings.vdex" "$IMG" 2>/dev/null || true
    "$DEBUGFS" -w -R "rmdir /app/Settings/oat/$_o" "$IMG" 2>/dev/null || true
  done
  "$DEBUGFS" -w -R "rmdir /app/Settings/oat" "$IMG" 2>/dev/null || true
  "$DEBUGFS" -w -R "rmdir /app/Settings" "$IMG" 2>/dev/null || true
  write_back "$ASSETS/Settings.apk" /priv-app/Settings/Settings.apk 0100644
else
  echo "=== stock Settings: keep /app/Settings (apk+odex), drop custom priv-app ==="
  "$DEBUGFS" -w -R "rm /priv-app/Settings/Settings.apk" "$IMG" 2>/dev/null || true
  "$DEBUGFS" -w -R "rmdir /priv-app/Settings" "$IMG" 2>/dev/null || true
  "$DEBUGFS" -R 'ls /app/Settings' "$IMG" 2>/dev/null || true
  "$DEBUGFS" -R 'ls /app/Settings/oat/arm' "$IMG" 2>/dev/null || true
fi

# Мок PackageManager.compareSignatures — всегда (сток и custom Settings)
if [[ ! -f "$ASSETS/services.jar" ]]; then
  echo "=== patch services.jar (compareSignatures mock) ==="
  "$ROOT/scripts/patch-services-pm-signatures.sh"
fi
echo "=== install deodexed /framework/services.jar (no odex) ==="
write_back "$ASSETS/services.jar" /framework/services.jar 0100644
"$DEBUGFS" -w -R "rm /framework/oat/arm/services.odex" "$IMG" 2>/dev/null || true
"$DEBUGFS" -w -R "rm /framework/oat/arm/services.vdex" "$IMG" 2>/dev/null || true
"$DEBUGFS" -w -R "rm /framework/oat/arm/services.art" "$IMG" 2>/dev/null || true

# UI extras: терминал, сеть, файлы, игра, браузер, Wi‑Fi хаб
echo "=== extras (TermOnePlus / WifiAnalyzer / Amaze / 2048 / Lightning / WifiHub) ==="
"$DEBUGFS" -w -R "mkdir /app/TermOnePlus" "$IMG" 2>/dev/null || true
"$DEBUGFS" -w -R "mkdir /app/WifiAnalyzer" "$IMG" 2>/dev/null || true
"$DEBUGFS" -w -R "mkdir /app/Amaze" "$IMG" 2>/dev/null || true
"$DEBUGFS" -w -R "mkdir /app/Game2048" "$IMG" 2>/dev/null || true
"$DEBUGFS" -w -R "mkdir /app/Lightning" "$IMG" 2>/dev/null || true
"$DEBUGFS" -w -R "mkdir /app/WifiHub" "$IMG" 2>/dev/null || true
write_back "$ASSETS/extras/TermOnePlus.apk" /app/TermOnePlus/TermOnePlus.apk 0100644
write_back "$ASSETS/extras/WifiAnalyzer.apk" /app/WifiAnalyzer/WifiAnalyzer.apk 0100644
write_back "$ASSETS/extras/Amaze.apk" /app/Amaze/Amaze.apk 0100644
write_back "$ASSETS/extras/Game2048.apk" /app/Game2048/Game2048.apk 0100644
write_back "$ASSETS/extras/Lightning.apk" /app/Lightning/Lightning.apk 0100644
write_back "$ASSETS/extras/WifiHub.apk" /app/WifiHub/WifiHub.apk 0100644

write_back "$ASSETS/magisk-arm/magisk" /xbin/magisk 0100755
write_back "$ASSETS/magisk-arm/magiskpolicy" /xbin/magiskpolicy 0100755
write_back "$ASSETS/magisk-arm/busybox" /xbin/busybox 0100755
# cytasu: рабочий root без Magisk boot-patch (ADVCA)
write_back "$ASSETS/magisk-arm/cytasu-daemon" /xbin/cytasu-daemon 0100755
write_back "$ASSETS/magisk-arm/su" /xbin/su 0100755
write_back "$ASSETS/magisk-arm/magisk" /bin/magisk 0100755
write_back "$ASSETS/magisk-arm/su" /bin/su 0100755
write_back "$ASSETS/bash-arm/bash" /xbin/bash 0100755
write_back "$ASSETS/bash-arm/bash" /bin/bash 0100755
if [[ -f "$ASSETS/bash-arm/inputrc" ]]; then
  write_back "$ASSETS/bash-arm/inputrc" /etc/inputrc 0100644
fi

"$DEBUGFS" -w -R "mkdir /etc/dropbear" "$IMG" 2>/dev/null || true
write_back "$ASSETS/ssh/authorized_keys" /etc/dropbear/authorized_keys 0100600
# Android 7 linker: clear DT_FLAGS_1 (DF_1_PIE|NOW) on NDK-built dropbear
python3 "$ROOT/scripts/elf-clear-dt-flags1.py" \
  "$ASSETS/dropbear-arm/dropbear" \
  "$ASSETS/dropbear-arm/dropbearkey" \
  "$ASSETS/dropbear-arm/scp" || true
write_back "$ASSETS/dropbear-arm/dropbear" /xbin/dropbear 0100755
write_back "$ASSETS/dropbear-arm/dropbearkey" /xbin/dropbearkey 0100755
write_back "$ASSETS/dropbear-arm/scp" /xbin/scp 0100755
write_back "$WORKDIR/dropbear.sh" /xbin/dropbear.sh 0100755

echo "=== e2fsck ==="
"$FSCK" -fy "$IMG" || true

echo "=== remaining /app ==="
"$DEBUGFS" -R 'ls /app' "$IMG" 2>/dev/null | tr -s '[:space:]' '\n' | grep -v '^[0-9.]*$' | grep -v '^$' | sort -u

echo "=== priv-app (launcher/root) ==="
"$DEBUGFS" -R 'ls /priv-app/Lawnchair' "$IMG" 2>/dev/null || true
"$DEBUGFS" -R 'ls /priv-app/Magisk' "$IMG" 2>/dev/null || true
"$DEBUGFS" -R 'ls /priv-app/Settings' "$IMG" 2>/dev/null || true
"$DEBUGFS" -R 'ls /app/TermOnePlus' "$IMG" 2>/dev/null || true
"$DEBUGFS" -R 'ls /app/WifiAnalyzer' "$IMG" 2>/dev/null || true
"$DEBUGFS" -R 'ls /app/Amaze' "$IMG" 2>/dev/null || true
"$DEBUGFS" -R 'ls /app/Game2048' "$IMG" 2>/dev/null || true
"$DEBUGFS" -R 'ls /app/Lightning' "$IMG" 2>/dev/null || true
"$DEBUGFS" -R 'ls /app/WifiHub' "$IMG" 2>/dev/null || true
"$DEBUGFS" -R 'ls /xbin' "$IMG" 2>/dev/null | tr -s ' ' '\n' | grep -E 'magisk|su|cytasu|busybox|bash|dropbear|uart|cytatv|adbd' || true
"$DEBUGFS" -R 'ls /etc/dropbear' "$IMG" 2>/dev/null || true
"$DEBUGFS" -R 'ls /etc/init' "$IMG" 2>/dev/null | tr -s ' ' '\n' | grep custom || true

echo "=== props ==="
"$DEBUGFS" -R 'cat /build.prop' "$IMG" 2>/dev/null | grep -E 'bootiptv|adb|custom|incremental|display.id|debuggable|type=|preferred|secure|uart.loglevel|sdlinux|total.memsize|total.flash' || true
"$DEBUGFS" -R 'cat /etc/build_hw.prop' "$IMG" 2>/dev/null | grep -E 'default.launcher' || true

cat > "$OUT/MANIFEST.txt" <<EOF
custom: Cyta dump, IPTV removed, Lawnchair HOME, cytasu root, Magisk app, dropbear :22, SD Linux chroot
logo   $(wc -c <"$OUT/logo.img")
kernel $(wc -c <"$OUT/kernel.img")
system $(wc -c <"$OUT/system.img")
launcher: ch.deletescape.lawnchair (Lawnchair 1.2.0)
settings: SETTINGS_SRC=$SETTINGS_SRC + services.jar compareSignatures mock (always)
apps: TermOnePlus, WifiAnalyzer, Amaze, 2048, Lightning, WifiHub (Wi‑Fi)
root: cytasu-daemon + /system/xbin/su (ADVCA — без Magisk boot-patch)
bash: /system/xbin/bash (Inknyto static ARM)
ssh: dropbear :22 — ключ assets/ssh/id_ed25519_q22e (или root с пустым паролем)
  ssh -i firmware/custom/assets/ssh/id_ed25519_q22e root@<IP>
adb: tcp :5555 (/system/xbin/adbd + adbd-watch); UART: cytatv-adbd / cytatv-adbd-watch
uart: logcat I + dedicated CRASH stream + tombstones → ttyAMA0 (persist.cytatv.uart.loglevel)
wifi: MT7662T cal+firmware; auto-enable после boot (persist.cytatv.wifi.enable=1)
sd-linux: /system/xbin/cytatv-sd-linux.sh — SD/USB e2d → SSH:22 + Enigma2 as root (persist.cytatv.sdlinux=1)
  manual: /system/xbin/cytatv-sd-linux.sh
  image: firmware/e2d/sd/e2d-android-chroot.img → prepare-sdcard.sh
rebuild: ./scripts/build-custom-android.sh
EOF

echo ""
echo "Done: $OUT"
ls -lh "$OUT"
