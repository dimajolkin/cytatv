#!/system/bin/sh
# -F: foreground — иначе fork + oneshot → init.svc.dropbear=stopped при живом демоне
case "$(getprop persist.cytatv.ssh)" in
  0) exit 0 ;;
esac
export HOME=/data/dropbear
mkdir -p /data/dropbear/.ssh
cp /system/etc/dropbear/authorized_keys /data/dropbear/.ssh/authorized_keys 2>/dev/null
chmod 700 /data/dropbear /data/dropbear/.ssh
chmod 600 /data/dropbear/.ssh/authorized_keys 2>/dev/null
cd /data/dropbear || exit 1
if [ -x /system/xbin/bash ]; then
  export SHELL=/system/xbin/bash
elif [ -x /system/bin/bash ]; then
  export SHELL=/system/bin/bash
fi
# -R hostkeys, -B пустой пароль root, ключ: assets/ssh/id_ed25519_q22e
exec /system/xbin/dropbear -F -R -p 22 -B
