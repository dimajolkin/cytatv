#!/system/bin/sh
# Эксперимент: чтение команд с UART RX (на Q22E железо может не принимать).
T=/dev/ttyAMA0
[ -c "$T" ] || exit 0
case "$(getprop persist.q22e.uart.shell)" in
  0|false|no) exit 0 ;;
esac
BB=/system/xbin/busybox
STTY=stty
[ -x "$BB" ] && STTY="$BB stty"
$STTY -F "$T" 115200 cs8 -cstopb -parenb raw -echo 2>/dev/null || true
{
  echo ""
  echo "=== cytatv uart-shell (RX) — Enter=run, help, exit ==="
  echo "# "
} >>"$T"
while true; do
  IFS= read -r line <"$T" 2>/dev/null || { sleep 2; continue; }
  line=$(printf '%s' "$line" | tr -d '\r\n')
  [ -z "$line" ] && { printf '# ' >>"$T"; continue; }
  case "$line" in
    exit|quit) echo "bye" >>"$T"; break ;;
    help)
      cat >>"$T" <<'EOF'
# cmds: id, getprop, ip addr, ifconfig eth0, reboot, setprop ...
EOF
      ;;
    reboot) reboot ;;
    *)
      echo "# $line" >>"$T"
      sh -c "$line" >>"$T" 2>&1
      ;;
  esac
  printf '# ' >>"$T"
done
