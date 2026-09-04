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
