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
