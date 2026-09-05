#!/system/bin/sh
# Mount Ubuntu/Debian rootfs (SD/USB) → chroot: SSH :22.
# UI handoff: auto on USB flash; on SD only if persist.q22e.sdlinux.ui=1.
T=/dev/ttyAMA0
[ -c "$T" ] || T=/dev/console
log() { echo "cytatv: sd-linux $*" >>"$T" 2>/dev/null; }

case "$(getprop persist.q22e.sdlinux)" in
  0|false|no) log "skip (persist.q22e.sdlinux=0)"; exit 0 ;;
esac

MNT=/mnt/linux
LOCK=/data/local/tmp/cytatv-sd-linux.lock
mkdir -p /data/local/tmp 2>/dev/null
if [ -f "$LOCK" ]; then
  old=$(cat "$LOCK" 2>/dev/null)
  [ -n "$old" ] && kill -0 "$old" 2>/dev/null && { log "already running pid=$old"; exit 0; }
fi
echo $$ >"$LOCK"

is_linux_rootfs() {
  [ -f "$1/etc/debian_version" ] || [ -f "$1/etc/cytatv-sd-linux" ] || grep -q 'ID=ubuntu' "$1/etc/os-release" 2>/dev/null
}

try_linux() {
  cand="$1"
  kind="$2"
  [ -b "$cand" ] || return 1
  mkdir -p "$MNT"
  if grep -q " $MNT " /proc/mounts 2>/dev/null; then
    is_linux_rootfs "$MNT" || { umount "$MNT" 2>/dev/null || true; return 1; }
    echo "$cand $kind"
    return 0
  fi
  if mount -t ext4 -o rw,noatime "$cand" "$MNT" 2>/dev/null \
    || mount -o rw,noatime "$cand" "$MNT" 2>/dev/null; then
    if is_linux_rootfs "$MNT"; then
      echo "$cand $kind"
      return 0
    fi
    umount "$MNT" 2>/dev/null || true
  fi
  return 1
}

find_linux() {
  # USB first: flash stick wins over SD when both present
  for c in \
    /dev/block/sda1 /dev/block/sda /dev/sda1 /dev/sda \
    /dev/block/sdb1 /dev/block/sdb /dev/sdb1 /dev/sdb
  do
    try_linux "$c" usb && return 0
  done
  for c in \
    /dev/block/mmcblk1p1 /dev/block/mmcblk1 \
    /dev/mmcblk1p1 /dev/mmcblk1 \
    /dev/block/vold/public:179,1 /dev/block/vold/179:1
  do
    try_linux "$c" sd && return 0
  done
  for c in /dev/block/sd[a-z] /dev/block/sd[a-z][0-9] \
           /dev/block/mmcblk1 /dev/block/mmcblk1p1 \
           /dev/block/platform/*/by-name/*; do
    case "$c" in
      *sd[a-z]*) try_linux "$c" usb && return 0 ;;
      *mmcblk1*) try_linux "$c" sd && return 0 ;;
    esac
  done
  return 1
}

FOUND=""
i=0
while [ "$i" -lt 60 ]; do
  FOUND=$(find_linux) && break
  i=$((i + 1))
  sleep 1
done

if [ -z "$FOUND" ]; then
  log "skip (no sd/usb linux)"
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

if [ -f /system/etc/resolv.conf ]; then
  cp /system/etc/resolv.conf "$MNT/etc/resolv.conf" 2>/dev/null || true
elif [ -f /etc/resolv.conf ]; then
  cp /etc/resolv.conf "$MNT/etc/resolv.conf" 2>/dev/null || true
else
  printf 'nameserver 8.8.8.8\nnameserver 1.1.1.1\n' >"$MNT/etc/resolv.conf" 2>/dev/null || true
fi

mkdir -p "$MNT/root/.ssh" 2>/dev/null
if [ -f /system/etc/dropbear/authorized_keys ]; then
  cp /system/etc/dropbear/authorized_keys "$MNT/root/.ssh/authorized_keys" 2>/dev/null || true
  chmod 700 "$MNT/root/.ssh" 2>/dev/null || true
  chmod 600 "$MNT/root/.ssh/authorized_keys" 2>/dev/null || true
fi

# Smoke: dynamic linker + /bin/sh must work (broken e2d had missing /usr/lib)
if ! chroot "$MNT" /bin/sh -c 'echo ok' >/dev/null 2>>"$T"; then
  log "chroot broken (no /bin/sh or missing libs) — keep Android UI"
  rm -f "$LOCK"
  exit 1
fi
log "started (chroot $MNT ok)"

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
    mkdir -p "$MNT/var/run/sshd" "$MNT/run/sshd" 2>/dev/null
    # host keys if missing
    if [ ! -f "$MNT/etc/ssh/ssh_host_ed25519_key" ] && [ -x "$MNT/usr/bin/ssh-keygen" ]; then
      chroot "$MNT" /usr/bin/ssh-keygen -A 2>>"$T" || true
    fi
    chroot "$MNT" /usr/sbin/sshd 2>>"$T" && log "sshd ok :22 (root)"
  elif [ -x "$MNT/sbin/dropbear" ]; then
    chroot "$MNT" /sbin/dropbear -R -p 22 2>>"$T" && log "dropbear ok :22 (root)"
  elif [ -x "$MNT/usr/sbin/dropbear" ]; then
    chroot "$MNT" /usr/sbin/dropbear -R -p 22 2>>"$T" && log "dropbear ok :22 (root)"
  else
    log "ssh fail (no sshd/dropbear)"
  fi
) &

# UI handoff: USB flash → auto; SD → only if prop set (or force-off with =0)
UI="$(getprop persist.q22e.sdlinux.ui)"
if [ "$KIND" = "usb" ]; then
  case "$UI" in
    0|false|no) ;;
    *)
      UI=1
      setprop persist.q22e.sdlinux.ui 1
      log "ui auto-set (usb)"
      ;;
  esac
fi
case "$UI" in
  1|true|yes)
    (
      sleep 3
      log "ui handoff: stop zygote/surfaceflinger"
      setprop ctl.stop zygote 2>/dev/null || true
      setprop ctl.stop zygote_secondary 2>/dev/null || true
      setprop ctl.stop surfaceflinger 2>/dev/null || true
    ) &
    ;;
  *)
    log "ui keep Android (usb flash → auto; or set persist.q22e.sdlinux.ui=1)"
    ;;
esac

exit 0
