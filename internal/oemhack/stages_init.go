package oemhack

import (
	"os"
	"strings"
)

func stageWriteInitAndHooks(b *Job) error {
	mode644 := "0100644"
	mode755 := "0100755"

	if err := b.WriteBack(b.work("build.prop"), "/build.prop", ""); err != nil {
		return err
	}
	if _, err := os.Stat(b.work("build_hw.prop")); err == nil {
		if err := b.WriteBack(b.work("build_hw.prop"), "/etc/build_hw.prop", ""); err != nil {
			return err
		}
	}
	if err := b.WriteBack(b.work("reserveAPP.xml"), "/etc/reserveAPP.xml", ""); err != nil {
		return err
	}

	b.Mkdir("/etc/init")
	for _, f := range []string{"custom_adb.rc", "custom_root.rc", "custom_ssh.rc", "custom_uart.rc", "custom_sdlinux.rc"} {
		if err := b.WriteBack(b.work(f), "/etc/init/"+f, ""); err != nil {
			return err
		}
	}

	b.Mkdir("/xbin")
	b.Mkdir("/mnt")
	b.Mkdir("/mnt/linux")

	for _, f := range []string{
		"uart-logcat.sh", "uart-crash.sh", "uart-shell.sh", "wifi-boot.sh",
		"adbd-tcp.sh", "adbd-watch.sh", "cytatv-sd-linux.sh",
		"cytatv-fix-uid.sh", "cytatv-boot.sh",
	} {
		if err := b.WriteBack(b.work(f), "/xbin/"+f, mode755); err != nil {
			return err
		}
	}
	if err := b.WriteBack(b.asset("adbd-arm", "adbd"), "/xbin/adbd", mode755); err != nil {
		return err
	}
	if _, err := os.Stat(b.asset("adb", "adb_keys")); err == nil {
		if err := b.WriteBack(b.asset("adb", "adb_keys"), "/etc/adb_keys", mode644); err != nil {
			return err
		}
		b.logf("adb_keys → /etc/adb_keys")
	}

	// patch init.bigfish.sh
	bigfish := b.work("init.bigfish.sh")
	if err := b.Dump("/etc/init.bigfish.sh", bigfish); err == nil {
		if err := patchInitBigfish(bigfish); err != nil {
			return err
		}
		if err := b.WriteBack(bigfish, "/etc/init.bigfish.sh", mode755); err != nil {
			return err
		}
		b.logf("init.bigfish.sh: cytatv-boot hook")
	} else {
		b.logf("WARN: нет /etc/init.bigfish.sh")
	}

	// append uart services to logd.rc
	logd := b.work("logd.rc")
	if err := b.Dump("/etc/init/logd.rc", logd); err == nil {
		data, err := os.ReadFile(logd)
		if err != nil {
			return err
		}
		text := string(data)
		if !strings.Contains(text, "uart_crash") {
			appendRC, err := scriptFS.ReadFile("scripts/logd_uart_append.rc")
			if err != nil {
				return err
			}
			text = strings.TrimRight(text, "\n") + "\n" + string(appendRC)
			if err := os.WriteFile(logd, []byte(text), 0o644); err != nil {
				return err
			}
			if err := b.WriteBack(logd, "/etc/init/logd.rc", ""); err != nil {
				return err
			}
			b.logf("logd.rc: uart_logcat + uart_crash appended")
		}
	}
	return nil
}

func patchInitBigfish(path string) error {
	data, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	text := string(data)

	// strip previous cytatv hooks (line-based; Go regexp has no lookahead)
	var cleaned []string
	skipBlock := false
	for _, line := range strings.SplitAfter(text, "\n") {
		trim := strings.TrimSpace(line)
		if strings.HasPrefix(trim, "# cytatv") {
			skipBlock = true
			continue
		}
		if skipBlock {
			if trim == "" || strings.HasPrefix(trim, "#") ||
				strings.Contains(trim, "cytatv-") ||
				strings.Contains(trim, "uart-logcat") ||
				strings.HasPrefix(trim, "echo \"=== cytatv") {
				continue
			}
			skipBlock = false
		}
		if strings.Contains(line, "/system/xbin/uart-logcat.sh") ||
			strings.Contains(line, "/system/xbin/cytatv-fix-uid.sh") ||
			strings.Contains(line, "/system/xbin/cytatv-boot.sh") {
			continue
		}
		cleaned = append(cleaned, line)
	}
	text = strings.Join(cleaned, "")

	early := "\n# cytatv early marker\n" +
		`echo "=== cytatv init.bigfish.sh ===" > /dev/ttyAMA0 2>/dev/null || ` +
		`echo "=== cytatv init.bigfish.sh ===" > /dev/console` + "\n"
	hook := "\n# cytatv boot: uid-patch (sync, до PM), затем остальное в фоне\n" +
		"[ -x /system/xbin/cytatv-fix-uid.sh ] && /system/xbin/cytatv-fix-uid.sh\n" +
		"[ -x /system/xbin/cytatv-boot.sh ] && /system/xbin/cytatv-boot.sh &\n"

	lines := strings.SplitAfter(text, "\n")
	var out []string
	inserted := false
	for _, line := range lines {
		if strings.HasPrefix(line, "#!") {
			out = append(out, line)
			if !strings.Contains(text, "cytatv early marker") {
				out = append(out, early)
			}
			inserted = true
			continue
		}
		out = append(out, line)
	}
	if !inserted {
		out = append([]string{"#!/system/bin/sh\n" + early}, out...)
	}
	if !strings.Contains(text, "cytatv-boot.sh ] && /system/xbin/cytatv-boot.sh") {
		out = append(out, hook)
	}
	return os.WriteFile(path, []byte(strings.Join(out, "")), 0o644)
}
