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
