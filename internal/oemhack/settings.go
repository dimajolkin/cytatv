package oemhack

import (
	"cytatv/internal/config"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
)

// EnsureRepo clones/updates app.Repo into app.SrcDir.
func EnsureRepo(b *Job, app config.SystemAppSpec) (string, error) {
	if app.Repo == "" || app.Ref == "" || app.SrcDir == "" {
		return "", fmt.Errorf("system_apps[%s]: repo, ref, src_dir обязательны", app.ID)
	}
	dir := app.SrcDir
	if !filepath.IsAbs(dir) {
		dir = filepath.Join(b.Cfg.Root, dir)
	}

	gitDir := filepath.Join(dir, ".git")
	if _, err := os.Stat(gitDir); err != nil {
		if err := os.MkdirAll(filepath.Dir(dir), 0o755); err != nil {
			return "", err
		}
		_ = os.RemoveAll(dir)
		b.logf("git clone %s@%s → %s", app.Repo, app.Ref, dir)
		cmd := exec.Command("git", "clone", "--depth", "1", "--branch", app.Ref, app.Repo, dir)
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		if err := cmd.Run(); err != nil {
			_ = os.RemoveAll(dir)
			cmd = exec.Command("git", "clone", "--depth", "1", app.Repo, dir)
			cmd.Stdout = os.Stdout
			cmd.Stderr = os.Stderr
			if err := cmd.Run(); err != nil {
				return "", fmt.Errorf("git clone %s: %w", app.Repo, err)
			}
			co := exec.Command("git", "-C", dir, "checkout", app.Ref)
			co.Stdout = os.Stdout
			co.Stderr = os.Stderr
			if err := co.Run(); err != nil {
				return "", fmt.Errorf("git checkout %s: %w", app.Ref, err)
			}
		}
	} else if app.Pull {
		b.logf("git fetch %s (%s)", dir, app.Ref)
		fetch := exec.Command("git", "-C", dir, "fetch", "--depth", "1", "origin", app.Ref)
		fetch.Stdout = os.Stdout
		fetch.Stderr = os.Stderr
		if err := fetch.Run(); err != nil {
			return "", err
		}
		co := exec.Command("git", "-C", dir, "checkout", "FETCH_HEAD")
		co.Stdout = os.Stdout
		co.Stderr = os.Stderr
		if err := co.Run(); err != nil {
			return "", err
		}
	}

	if _, err := os.Stat(filepath.Join(dir, "Makefile")); err != nil {
		return "", fmt.Errorf("нет Makefile в %s", dir)
	}
	return dir, nil
}

// MakeAPK runs make <target> FIRMWARE_ASSETS=… in srcDir.
func MakeAPK(srcDir, makeTarget, assetsDir string) error {
	if makeTarget == "" {
		return fmt.Errorf("make_target пуст")
	}
	cmd := exec.Command("make", "-C", srcDir, makeTarget, "FIRMWARE_ASSETS="+assetsDir)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

func stageSystemApps(b *Job) error {
	if len(b.Cfg.SystemApps) == 0 {
		b.logf("system_apps: пусто — skip")
		return nil
	}
	if err := os.MkdirAll(b.Cfg.AssetsDir, 0o755); err != nil {
		return err
	}
	for _, app := range b.Cfg.SystemApps {
		if err := buildSystemApp(b, app); err != nil {
			return err
		}
	}
	return nil
}

func buildSystemApp(b *Job, app config.SystemAppSpec) error {
	if app.ID == "" || app.APK == "" {
		return fmt.Errorf("system_apps: id и apk обязательны")
	}
	if app.UID != 0 && app.UID != 1000 {
		return fmt.Errorf("system_apps[%s]: пока поддерживается только uid=1000 (got %d)", app.ID, app.UID)
	}
	apk := b.asset(app.APK)
	if app.SkipBuild {
		b.logf("system_apps[%s]: skip_build", app.ID)
		return mustExist(apk)
	}
	if app.Repo == "" {
		return mustExist(apk)
	}
	src, err := EnsureRepo(b, app)
	if err != nil {
		return err
	}
	b.logf("system_apps[%s] uid=%d → %s", app.ID, app.UID, apk)
	if err := MakeAPK(src, app.MakeTarget, b.Cfg.AssetsDir); err != nil {
		return err
	}
	return mustExist(apk)
}

// BuildSystemApps is used by CLI `q22e settings`.
func BuildSystemApps(cfg Config) error {
	b, err := NewJob(cfg)
	if err != nil {
		return err
	}
	defer b.Close()
	return stageSystemApps(b)
}
