package oemhack

import (
	"os"
	"regexp"
	"strings"
)

func setProp(text, key, value string) string {
	pat := regexp.MustCompile(`(?m)^` + regexp.QuoteMeta(key) + `=.*$`)
	line := key + "=" + value
	if pat.MatchString(text) {
		return pat.ReplaceAllString(text, line)
	}
	return strings.TrimRight(text, "\n") + "\n" + line + "\n"
}

func delProp(text, key string) string {
	pat := regexp.MustCompile(`(?m)^` + regexp.QuoteMeta(key) + `=.*\n?`)
	return pat.ReplaceAllString(text, "")
}

func stagePatchPropsAndScripts(b *Job) error {
	if err := b.materializeScripts(); err != nil {
		return err
	}

	_ = b.Dump("/build.prop", b.work("build.prop"))
	_ = b.Dump("/etc/build_hw.prop", b.work("build_hw.prop"))
	_ = b.Dump("/etc/reserveAPP.xml", b.work("reserveAPP.xml"))

	bpBytes, err := os.ReadFile(b.work("build.prop"))
	if err != nil {
		return err
	}
	bp := string(bpBytes)
	for _, k := range []string{
		"ro.product.bootiptv",
		"persist.sys.iptv.connecthdcp",
		"ro.dolby.iptvcert.enable",
	} {
		bp = delProp(bp, k)
	}
	for k, v := range map[string]string{
		"ro.product.bootiptv":           "false",
		"persist.sys.iptv.connecthdcp":  "false",
		"ro.adb.secure":                 "0",
		"persist.sys.usb.config":        "none",
		"service.adb.tcp.port":          "5555",
		"persist.adb.tcp.port":          "5555",
		"persist.service.adb.enable":    "1",
		"persist.service.consoleenable": "1",
		"persist.q22e.uart.loglevel":  "I",
		"persist.q22e.uart.shell":     "1",
		"persist.q22e.wifi.enable":    "1",
		"persist.q22e.sdlinux":        "1",
		"ro.debuggable":                 "1",
		"ro.secure":                     "0",
		"ro.allow.mock.location":        "1",
		"ro.custom.q22e":                "oem-removed",
		"ro.build.display.id":           "Q22E-custom debloat",
		"ro.build.version.incremental":  "custom-1",
		"ro.total.memsize":              "2097152",
		"ro.total.flash":                "8G",
		"ro.build.type":                 "userdebug",
		"ro.build.tags":                 "test-keys",
		"ro.oem_preferred_pkg":          b.Cfg.Launcher.PreferredPkg,
	} {
		bp = setProp(bp, k, v)
	}
	bp = strings.ReplaceAll(bp, "LCYT03.SPC006.B002", "custom")
	bp = regexp.MustCompile(`(?i)cytacyta`).ReplaceAllString(bp, "custom")
	if err := os.WriteFile(b.work("build.prop"), []byte(bp), 0o644); err != nil {
		return err
	}
	b.logf("build.prop OK")

	hwPath := b.work("build_hw.prop")
	if _, err := os.Stat(hwPath); err == nil {
		hwBytes, err := os.ReadFile(hwPath)
		if err != nil {
			return err
		}
		hw := string(hwBytes)
		hw = delProp(hw, "ro.product.stb.vmxClientVersion")
		hw = delProp(hw, "ro.product.stb.vmxTaVersion")
		for k, v := range map[string]string{
			"ro.hw.sys.net.add.iptvroute": "0",
			"ro.hw.sys.default.launcher":  b.Cfg.Launcher.DefaultLauncher,
			"ro.hw.sys.boot.haswizard":    "0",
			"ro.hw.sys.net.dhcp.opt60":    "0",
			"ro.hw.sys.net.dhcp.opt61":    "0",
			"ro.hw.sys.net.dhcp.opt121":   "0",
		} {
			hw = setProp(hw, k, v)
		}
		if err := os.WriteFile(hwPath, []byte(hw), 0o644); err != nil {
			return err
		}
		b.logf("build_hw.prop OK")
	}

	if err := os.WriteFile(b.work("reserveAPP.xml"), []byte(renderReserveAPP(b.Cfg.ReserveApps)), 0o644); err != nil {
		return err
	}
	b.logf("reserveAPP.xml OK (%d apps)", len(b.Cfg.ReserveApps))
	return nil
}

func renderReserveAPP(pkgs []string) string {
	var b strings.Builder
	b.WriteString("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<Application>\n")
	for _, p := range pkgs {
		p = strings.TrimSpace(p)
		if p == "" {
			continue
		}
		b.WriteString("  <app packageName=\"")
		b.WriteString(p)
		b.WriteString("\"><persist>true</persist></app>\n")
	}
	b.WriteString("</Application>\n")
	return b.String()
}
