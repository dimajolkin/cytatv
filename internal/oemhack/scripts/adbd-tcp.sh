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
