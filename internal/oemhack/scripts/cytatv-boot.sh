#!/system/bin/sh
T=/dev/ttyAMA0
[ -c "$T" ] || T=/dev/console
echo "=== cytatv-boot.sh ===" >>"$T" 2>/dev/null

echo 0 > /sys/fs/selinux/enforce 2>/dev/null

# uid-patch: не блокируем boot, если packages.xml ещё нет (first boot)
[ -x /system/xbin/cytatv-fix-uid.sh ] && /system/xbin/cytatv-fix-uid.sh
echo "cytatv: fix-uid exit=$?" >>"$T" 2>/dev/null

# --- root gate: q22esu + su must work, иначе STOP zygote ---
(
  echo "=== q22e root-check ===" >>"$T" 2>/dev/null
  mkdir -p /data/adb/magisk /data/local/tmp 2>/dev/null
  SU=/system/xbin/su
  [ -x "$SU" ] || SU=/system/bin/su

  if [ ! -x "$SU" ] || [ ! -x /system/xbin/q22esu-daemon ]; then
    echo "q22e: ========================================" >>"$T" 2>/dev/null
    echo "q22e: FATAL no su/q22esu-daemon on system" >>"$T" 2>/dev/null
    echo "q22e: STOP zygote (no root)" >>"$T" 2>/dev/null
    echo "q22e: ========================================" >>"$T" 2>/dev/null
    setprop q22e.root.ok 0
    sleep 1
    stop zygote
    stop
    exit 1
  fi

  ensure_su_daemon() {
    [ -S /dev/q22esu.sock ] && pidof q22esu-daemon >/dev/null 2>&1 && return 0
    setprop ctl.start q22esu_daemon 2>/dev/null || true
    if ! pidof q22esu-daemon >/dev/null 2>&1; then
      /system/xbin/q22esu-daemon >/dev/null 2>&1 &
    fi
    [ -x /system/xbin/magisk ] && /system/xbin/magisk --daemon >/dev/null 2>&1
  }

  i=0
  ID0=
  ID1=
  while [ "$i" -lt 60 ]; do
    ensure_su_daemon
    ID0=$("$SU" 0 -c id 2>/dev/null)
    ID1=$("$SU" 1000 -c id 2>/dev/null)
    echo "$ID0" | grep -q 'uid=0' && echo "$ID1" | grep -q 'uid=1000' && break
    i=$((i + 1))
    sleep 1
  done

  echo "q22e: su0=$ID0" >>"$T" 2>/dev/null
  echo "q22e: su1000=$ID1" >>"$T" 2>/dev/null

  if ! echo "$ID0" | grep -q 'uid=0' || ! echo "$ID1" | grep -q 'uid=1000'; then
    echo "q22e: ========================================" >>"$T" 2>/dev/null
    echo "q22e: FATAL root not ready (su 0 / su 1000)" >>"$T" 2>/dev/null
    echo "q22e: sock=$( [ -S /dev/q22esu.sock ] && echo yes || echo no ) daemon=$(pidof q22esu-daemon)" >>"$T" 2>/dev/null
    echo "q22e: STOP zygote (boot broken on purpose)" >>"$T" 2>/dev/null
    echo "q22e: ========================================" >>"$T" 2>/dev/null
    setprop q22e.root.ok 0
    sleep 1
    stop zygote
    stop
    exit 1
  fi

  echo "q22e: root OK (uid 0)" >>"$T" 2>/dev/null
  echo "q22e: system OK (uid 1000)" >>"$T" 2>/dev/null
  setprop q22e.root.ok 1
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
  i=0
  while [ "$i" -lt 90 ]; do
    [ -d /data ] && break
    i=$((i + 1))
    sleep 2
  done
  # fallback if init service ещё не поднял (-F в dropbear.sh → нужен фон)
  if ! pidof dropbear >/dev/null 2>&1; then
    [ -x /system/xbin/dropbear.sh ] && /system/xbin/dropbear.sh &
  fi
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
    setprop q22e.settings.uid_ok 0
    sleep 1
    stop zygote
    stop
    exit 1
  fi

  echo "cytatv: Settings UID OK (1000)" >>"$T" 2>/dev/null
  setprop q22e.settings.uid_ok 1
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
