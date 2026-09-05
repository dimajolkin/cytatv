package oemhack

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"cytatv/internal/config"
)

// Test verifies an already-built system.img against yaml (read-only debugfs).
func Test(cfg config.Config) error {
	pipe := pipelineFromConfig(cfg)
	b, err := NewJob(pipe)
	if err != nil {
		return err
	}
	defer b.Close()

	if _, err := os.Stat(b.Img); err != nil {
		return fmt.Errorf("нет %s — сначала android-oem-hack build", b.Img)
	}

	b.logf("=== android-oem-hack test → %s ===", b.Img)
	var fails []string
	check := func(ok bool, name, detail string) {
		if ok {
			b.logf("OK  %s", name)
			return
		}
		b.logf("FAIL %s — %s", name, detail)
		fails = append(fails, name+": "+detail)
	}

	for _, app := range b.Cfg.InstallApps {
		host := b.asset(app.APK)
		if _, err := os.Stat(host); err != nil {
			if app.Optional {
				b.logf("SKIP install %s (optional, no asset)", app.APK)
				continue
			}
			check(false, "install:"+app.APK, "нет asset "+app.APK)
			continue
		}
		check(b.Stat(app.Guest), "install:"+app.Guest, "guest отсутствует")
		guestDir := filepath.ToSlash(filepath.Dir(app.Guest))
		for _, rep := range app.Replace {
			rep = filepath.ToSlash(rep)
			if rep == guestDir || rep == app.Guest {
				continue
			}
			if b.Stat(rep) {
				check(false, "replace:"+rep, "должен быть удалён")
			} else {
				check(true, "replace:"+rep, "")
			}
		}
	}

	for _, app := range b.Cfg.SystemApps {
		check(b.Stat(app.Guest), "system_app:"+app.Guest, "guest отсутствует")
	}

	bp, err := b.Cat("/build.prop")
	if err != nil {
		check(false, "build.prop", err.Error())
	} else {
		want := b.Cfg.Launcher.PreferredPkg
		got := propValue(bp, "ro.oem_preferred_pkg")
		check(got == want, "launcher.preferred_pkg", fmt.Sprintf("want %q got %q", want, got))
	}

	hw, err := b.Cat("/etc/build_hw.prop")
	if err != nil {
		check(false, "build_hw.prop", err.Error())
	} else {
		want := b.Cfg.Launcher.DefaultLauncher
		got := propValue(hw, "ro.hw.sys.default.launcher")
		check(got == want, "launcher.default_launcher", fmt.Sprintf("want %q got %q", want, got))
	}

	res, err := b.Cat("/etc/reserveAPP.xml")
	if err != nil {
		check(false, "reserveAPP.xml", err.Error())
	} else {
		for _, pkg := range b.Cfg.ReserveApps {
			pkg = strings.TrimSpace(pkg)
			if pkg == "" {
				continue
			}
			ok := reserveHasPackage(res, pkg)
			check(ok, "reserve:"+pkg, "нет в reserveAPP.xml")
		}
	}

	if len(fails) > 0 {
		return fmt.Errorf("test: %d FAIL", len(fails))
	}
	b.logf("test: all OK")
	return nil
}

func propValue(text, key string) string {
	prefix := key + "="
	for _, line := range strings.Split(text, "\n") {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, "#") {
			continue
		}
		if strings.HasPrefix(line, prefix) {
			return strings.TrimSpace(strings.TrimPrefix(line, prefix))
		}
	}
	return ""
}

func reserveHasPackage(xml, pkg string) bool {
	needle := `packageName="` + pkg + `"`
	return strings.Contains(xml, needle)
}
