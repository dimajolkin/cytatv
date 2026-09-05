#!/system/bin/sh
T=/dev/ttyAMA0
[ -c "$T" ] || T=/dev/console
LEVEL=$(getprop persist.q22e.uart.loglevel)
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
