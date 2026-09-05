package oemhack

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
)

func stageE2fsck(b *Job) error {
	cmd := exec.Command(b.Cfg.E2fsck, "-fy", b.Img)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	_ = cmd.Run() // bash: || true
	return nil
}

func stageManifest(b *Job) error {
	if ls, err := b.Ls("/app"); err == nil {
		b.logf("remaining /app:")
		for _, line := range tokenizeLs(ls) {
			b.logf("  %s", line)
		}
	}
	for _, p := range []string{
		"/priv-app/Magisk", "/priv-app/Settings",
		"/app/TermOnePlus", "/app/WifiAnalyzer", "/app/Amaze",
		"/app/Game2048", "/app/Lightning", "/app/WifiHub",
		"/etc/dropbear",
	} {
		if ls, err := b.Ls(p); err == nil {
			b.logf("%s: %s", p, strings.TrimSpace(collapseWS(ls)))
		}
	}
	if ls, err := b.Ls("/xbin"); err == nil {
		re := regexp.MustCompile(`magisk|su|cytasu|busybox|bash|dropbear|uart|cytatv|adbd`)
		for _, tok := range tokenizeLs(ls) {
			if re.MatchString(tok) {
				b.logf("  /xbin/%s", tok)
			}
		}
	}
	if ls, err := b.Ls("/etc/init"); err == nil {
		for _, tok := range tokenizeLs(ls) {
			if strings.Contains(tok, "custom") {
				b.logf("  /etc/init/%s", tok)
			}
		}
	}
	if cat, err := b.Cat("/build.prop"); err == nil {
		re := regexp.MustCompile(`bootiptv|adb|custom|incremental|display.id|debuggable|type=|preferred|secure|uart.loglevel|sdlinux|total.memsize|total.flash`)
		b.logf("props:")
		for _, line := range strings.Split(cat, "\n") {
			if re.MatchString(line) {
				b.logf("  %s", line)
			}
		}
	}

	logoSz := fileSize(filepath.Join(b.Cfg.OutDir, "logo.img"))
	kernSz := fileSize(filepath.Join(b.Cfg.OutDir, "kernel.img"))
	sysSz := fileSize(b.Img)
	var appIDs []string
	for _, a := range b.Cfg.SystemApps {
		appIDs = append(appIDs, fmt.Sprintf("%s(uid=%d)", a.ID, a.UID))
	}
	manifest := fmt.Sprintf(`android-oem-hack: Cyta dump, IPTV removed, Settings HOME, cytasu root, Magisk app, dropbear :22, SD Linux chroot
logo   %d
kernel %d
system %d
launcher: com.android.settings (Q22E Settings = HOME)
system_apps: %s + services.jar compareSignatures mock
apps: TermOnePlus, WifiAnalyzer, Amaze, 2048, Lightning, WifiHub (Wi‑Fi)
root: cytasu-daemon + /system/xbin/su (ADVCA — без Magisk boot-patch)
bash: /system/xbin/bash (Inknyto static ARM)
ssh: dropbear :22 — ключ assets/ssh/id_ed25519_q22e
adb: tcp :5555 (/system/xbin/adbd + adbd-watch)
uart: logcat I + crashes → ttyAMA0
wifi: MT7662T cal+firmware; persist.cytatv.wifi.enable=1
sd-linux: cytatv-sd-linux.sh — persist.cytatv.sdlinux=1; UI auto on USB
rebuild: go run ./cmd/q22e android-oem-hack build
`, logoSz, kernSz, sysSz, strings.Join(appIDs, ", "))
	return os.WriteFile(filepath.Join(b.Cfg.OutDir, "MANIFEST.txt"), []byte(manifest), 0o644)
}

func fileSize(p string) int64 {
	st, err := os.Stat(p)
	if err != nil {
		return 0
	}
	return st.Size()
}

func tokenizeLs(s string) []string {
	var out []string
	for _, tok := range strings.Fields(s) {
		if tok == "" || tok == "." || tok == ".." {
			continue
		}
		if strings.HasPrefix(tok, "(") || strings.HasSuffix(tok, ")") {
			continue
		}
		if tok == "debugfs" || strings.Contains(tok, "Mar-") {
			continue
		}
		if matched, _ := regexp.MatchString(`^[0-9.]+$`, tok); matched {
			continue
		}
		out = append(out, tok)
	}
	return out
}

func collapseWS(s string) string {
	return strings.Join(strings.Fields(s), " ")
}
