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
[[ -f "$ASSETS/magisk-arm/magisk" ]] || { echo "нет $ASSETS/magisk-arm/* — извлеки из Magisk.apk"; exit 1; }
[[ -f "$ASSETS/dropbear-arm/dropbear" ]] || { echo "нет $ASSETS/dropbear-arm/dropbear"; exit 1; }
[[ -f "$ASSETS/ssh/authorized_keys" ]] || { echo "нет $ASSETS/ssh/authorized_keys"; exit 1; }
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
    "Settings",
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
    ("persist.sys.usb.config", "adb"),
    ("service.adb.tcp.port", "5555"),
    ("persist.adb.tcp.port", "5555"),
    ("persist.service.adb.enable", "1"),
    ("persist.service.consoleenable", "1"),
    # V=всё на UART (115200 может сыпать); I/D — тише: setprop persist.cytatv.uart.loglevel I
    ("persist.cytatv.uart.loglevel", "V"),
    ("ro.debuggable", "1"),
    ("ro.secure", "0"),
    ("ro.allow.mock.location", "1"),
    ("ro.custom.cytatv", "cyta-removed"),
    ("ro.build.display.id", "Q22E-custom debloat"),
    # fingerprint без LCYT03/cyta в отображаемой части — оставляем валидный формат
    ("ro.build.version.incremental", "custom-1"),
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

cat > "$WORKDIR/custom_adb.rc" <<'RC'
# TCP ADB как можно раньше — boot_completed на STB иногда ненадёжен
on early-boot
    setprop service.adb.tcp.port 5555
    setprop persist.adb.tcp.port 5555
    setprop persist.sys.usb.config adb
    setprop persist.service.adb.enable 1

on boot
    setprop service.adb.tcp.port 5555
    setprop persist.adb.tcp.port 5555
    setprop ctl.start adbd

on property:sys.boot_completed=1
    setprop service.adb.tcp.port 5555
    setprop persist.adb.tcp.port 5555
    setprop persist.sys.usb.config adb
    setprop persist.service.adb.enable 1
    setprop ctl.start adbd

on property:init.svc.adbd=stopped
    setprop ctl.start adbd
RC

# Kernel ADVCA — Magisk boot-patch недоступен. Root через system + permissive.
cat > "$WORKDIR/custom_root.rc" <<'RC'
on early-init
    write /sys/fs/selinux/enforce 0

on post-fs-data
    mkdir /data/adb 0700 root root
    mkdir /data/adb/magisk 0755 root root
    start magisk_daemon

service magisk_daemon /system/xbin/magisk --daemon
    user root
    group root
    oneshot
    disabled

on property:sys.boot_completed=1
    write /sys/fs/selinux/enforce 0
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

# Kernel уже на console=ttyAMA0; зеркалим Android logcat туда же (RX по-прежнему мёртв).
cat > "$WORKDIR/uart-logcat.sh" <<'SH'
#!/system/bin/sh
T=/dev/ttyAMA0
[ -c "$T" ] || T=/dev/console
LEVEL=$(getprop persist.cytatv.uart.loglevel)
[ -z "$LEVEL" ] && LEVEL=V
{
  echo ""
  echo "=== cytatv uart-logcat *:${LEVEL} → $T ==="
} >"$T"
# -b all: main/system/radio/events/crash (Android 7)
exec /system/bin/logcat -v threadtime -b all "*:${LEVEL}" >"$T" 2>&1
SH

cat > "$WORKDIR/custom_uart.rc" <<'RC'
on early-boot
    write /proc/sys/kernel/printk "7 4 1 7"

on property:init.svc.logd=running
    start uart_logcat

on property:sys.boot_completed=1
    start uart_logcat

service uart_logcat /system/xbin/uart-logcat.sh
    user root
    group root system log
    oneshot
    disabled

on property:init.svc.uart_logcat=stopped
    start uart_logcat
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
"$DEBUGFS" -w -R "mkdir /xbin" "$IMG" 2>/dev/null || true
write_back "$WORKDIR/uart-logcat.sh" /xbin/uart-logcat.sh 0100755

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

echo "=== Lawnchair + Magisk (priv-app) + su + dropbear ==="
"$DEBUGFS" -w -R "mkdir /priv-app/Lawnchair" "$IMG" 2>/dev/null || true
"$DEBUGFS" -w -R "mkdir /priv-app/Magisk" "$IMG" 2>/dev/null || true
write_back "$ASSETS/Lawnchair.apk" /priv-app/Lawnchair/Lawnchair.apk 0100644
write_back "$ASSETS/Magisk.apk" /priv-app/Magisk/Magisk.apk 0100644

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
write_back "$ASSETS/magisk-arm/magisk" /xbin/su 0100755
write_back "$ASSETS/magisk-arm/magiskpolicy" /xbin/magiskpolicy 0100755
write_back "$ASSETS/magisk-arm/busybox" /xbin/busybox 0100755
# также в bin на случай PATH
write_back "$ASSETS/magisk-arm/magisk" /bin/magisk 0100755
write_back "$ASSETS/magisk-arm/magisk" /bin/su 0100755

"$DEBUGFS" -w -R "mkdir /etc/dropbear" "$IMG" 2>/dev/null || true
write_back "$ASSETS/ssh/authorized_keys" /etc/dropbear/authorized_keys 0100600
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
"$DEBUGFS" -R 'ls /app/TermOnePlus' "$IMG" 2>/dev/null || true
"$DEBUGFS" -R 'ls /app/WifiAnalyzer' "$IMG" 2>/dev/null || true
"$DEBUGFS" -R 'ls /app/Amaze' "$IMG" 2>/dev/null || true
"$DEBUGFS" -R 'ls /app/Game2048' "$IMG" 2>/dev/null || true
"$DEBUGFS" -R 'ls /app/Lightning' "$IMG" 2>/dev/null || true
"$DEBUGFS" -R 'ls /app/WifiHub' "$IMG" 2>/dev/null || true
"$DEBUGFS" -R 'ls /xbin' "$IMG" 2>/dev/null | tr -s ' ' '\n' | grep -E 'magisk|su|busybox|dropbear|uart' || true
"$DEBUGFS" -R 'ls /etc/dropbear' "$IMG" 2>/dev/null || true
"$DEBUGFS" -R 'ls /etc/init' "$IMG" 2>/dev/null | tr -s ' ' '\n' | grep custom || true

echo "=== props ==="
"$DEBUGFS" -R 'cat /build.prop' "$IMG" 2>/dev/null | grep -E 'bootiptv|adb|custom|incremental|display.id|debuggable|type=|preferred|secure|uart.loglevel' || true
"$DEBUGFS" -R 'cat /etc/build_hw.prop' "$IMG" 2>/dev/null | grep -E 'default.launcher' || true

cat > "$OUT/MANIFEST.txt" <<EOF
custom: Cyta dump, IPTV removed, Lawnchair HOME, Magisk system-root, dropbear :22
logo   $(wc -c <"$OUT/logo.img")
kernel $(wc -c <"$OUT/kernel.img")
system $(wc -c <"$OUT/system.img")
launcher: ch.deletescape.lawnchair
apps: TermOnePlus, WifiAnalyzer, Amaze, 2048, Lightning, WifiHub (Wi‑Fi)
root: /system/xbin/su (Magisk, ADVCA kernel — без boot-patch)
ssh: dropbear :22 — ключ assets/ssh/id_ed25519_q22e (или root с пустым паролем)
  ssh -i firmware/custom/assets/ssh/id_ed25519_q22e root@<IP>
uart: kernel console + logcat -b all *:V → ttyAMA0 (persist.cytatv.uart.loglevel)
rebuild: ./scripts/build-custom-android.sh
EOF

echo ""
echo "Done: $OUT"
ls -lh "$OUT"
