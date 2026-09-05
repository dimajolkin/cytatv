package oemhack

import (
	"cytatv/internal/config"
	"fmt"
	"os"
	"path/filepath"
)

func stageInstallApps(b *Job) error {
	mode644 := "0100644"

	for _, app := range b.Cfg.InstallApps {
		if err := installAssetApp(b, app, mode644); err != nil {
			return err
		}
	}

	for _, app := range b.Cfg.SystemApps {
		if err := installSystemApp(b, app, mode644); err != nil {
			return err
		}
	}

	services := b.asset("services.jar")
	if _, err := os.Stat(services); err != nil {
		b.logf("patch services.jar (compareSignatures mock)")
		if err := b.PatchServicesJar(); err != nil {
			return err
		}
	}
	b.logf("install /framework/services.jar")
	if err := b.WriteBack(services, "/framework/services.jar", mode644); err != nil {
		return err
	}
	b.Rm("/framework/oat/arm/services.odex")
	b.Rm("/framework/oat/arm/services.vdex")
	b.Rm("/framework/oat/arm/services.art")
	return nil
}

func installAssetApp(b *Job, app config.InstallAppSpec, mode string) error {
	host := b.asset(app.APK)
	if _, err := os.Stat(host); err != nil {
		if app.Optional {
			b.logf("skip optional install %s: %v", app.APK, err)
			return nil
		}
		return fmt.Errorf("install_apps %s: %w", app.APK, err)
	}
	b.logf("install %s → %s", app.APK, app.Guest)
	for _, p := range app.Replace {
		b.RmTree(p)
		b.Rm(p)
	}
	guestDir := filepath.ToSlash(filepath.Dir(app.Guest))
	b.Rm(app.Guest)
	b.Rmdir(guestDir)
	b.Mkdir(guestDir)
	return b.WriteBack(host, app.Guest, mode)
}

func installSystemApp(b *Job, app config.SystemAppSpec, mode string) error {
	if app.Guest == "" || app.APK == "" {
		return fmt.Errorf("system_apps[%s]: guest и apk обязательны для install", app.ID)
	}
	b.logf("install %s (uid=%d) → %s", app.ID, app.UID, app.Guest)
	guestDir := filepath.ToSlash(filepath.Dir(app.Guest))
	b.Rm(app.Guest)
	b.Rmdir(guestDir)
	b.Mkdir(guestDir)
	if stock := app.RemoveStock; stock != "" {
		name := filepath.Base(stock)
		b.Rm(stock + "/" + name + ".apk")
		for _, o := range []string{"arm", "arm64"} {
			b.Rm(stock + "/oat/" + o + "/" + name + ".odex")
			b.Rm(stock + "/oat/" + o + "/" + name + ".vdex")
			b.Rmdir(stock + "/oat/" + o)
		}
		b.Rmdir(stock + "/oat")
		b.Rmdir(stock)
	}
	return b.WriteBack(b.asset(app.APK), app.Guest, mode)
}

func stageInstallRootTools(b *Job) error {
	mode755 := "0100755"
	mode600 := "0100600"
	mode644 := "0100644"

	writes := []struct{ host, guest string }{
		{b.asset("magisk-arm", "magisk"), "/xbin/magisk"},
		{b.asset("magisk-arm", "magiskpolicy"), "/xbin/magiskpolicy"},
		{b.asset("magisk-arm", "busybox"), "/xbin/busybox"},
		{b.asset("magisk-arm", "magisk"), "/bin/magisk"},
		{b.asset("bash-arm", "bash"), "/xbin/bash"},
		{b.asset("bash-arm", "bash"), "/bin/bash"},
	}
	if b.Cfg.InstallSu {
		writes = append(writes,
			struct{ host, guest string }{b.asset("magisk-arm", "q22esu-daemon"), "/xbin/q22esu-daemon"},
			struct{ host, guest string }{b.asset("magisk-arm", "su"), "/xbin/su"},
			struct{ host, guest string }{b.asset("magisk-arm", "su"), "/bin/su"},
		)
	}
	for _, w := range writes {
		if err := b.WriteBack(w.host, w.guest, mode755); err != nil {
			return err
		}
	}
	if _, err := os.Stat(b.asset("bash-arm", "inputrc")); err == nil {
		_ = b.WriteBack(b.asset("bash-arm", "inputrc"), "/etc/inputrc", mode644)
	}

	b.Mkdir("/etc/dropbear")
	if err := b.WriteBack(b.asset("ssh", "authorized_keys"), "/etc/dropbear/authorized_keys", mode600); err != nil {
		return err
	}

	db := []string{
		b.asset("dropbear-arm", "dropbear"),
		b.asset("dropbear-arm", "dropbearkey"),
		b.asset("dropbear-arm", "scp"),
	}
	clearDTFlags1Files(db...)

	for _, name := range []string{"dropbear", "dropbearkey", "scp"} {
		if err := b.WriteBack(b.asset("dropbear-arm", name), "/xbin/"+name, mode755); err != nil {
			return err
		}
	}
	return b.WriteBack(b.work("dropbear.sh"), "/xbin/dropbear.sh", mode755)
}
