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
