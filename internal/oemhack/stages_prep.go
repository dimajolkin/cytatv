package oemhack

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"

	"cytatv/internal/config"
)

func stageValidate(b *Job) error {
	if err := mustExist(b.Cfg.Debugfs); err != nil {
		return fmt.Errorf("%w — brew install e2fsprogs", err)
	}
	if err := mustExist(b.part("system.img")); err != nil {
		return err
	}
	if len(b.Cfg.Assets) == 0 {
		return fmt.Errorf("configs: assets[] пуст — перечисли файлы в android-oem-hack.yaml")
	}
	return nil
}

func stageFetchBins(b *Job) error {
	if err := os.MkdirAll(b.Cfg.AssetsDir, 0o755); err != nil {
		return err
	}
	for i := range b.Cfg.Assets {
		a := &b.Cfg.Assets[i]
		if a.Path == "" {
			return fmt.Errorf("assets[%d]: path обязателен", i)
		}
		if err := b.ensureAsset(a); err != nil {
			if a.Optional {
				b.logf("skip optional %s: %v", a.Path, err)
				continue
			}
			return err
		}
	}
	return nil
}

func (b *Job) ensureAsset(a *config.AssetSpec) error {
	dest := b.asset(a.Path)
	if _, err := os.Stat(dest); err == nil {
		return b.finalizeAsset(a, dest)
	}

	if a.Extract != nil && (a.URL != "" || a.From != "") {
		src := a.URL
		if a.From != "" {
			src = a.From
		}
		b.logf("extract %s ← %s", a.Path, src)
		if err := b.downloadExtract(a); err != nil {
			return err
		}
		return b.finalizeAsset(a, dest)
	}

	if a.URL != "" {
		b.logf("download %s ← %s", a.Path, a.URL)
		if err := os.MkdirAll(filepath.Dir(dest), 0o755); err != nil {
			return err
		}
		tmp := dest + ".partial"
		if err := download(a.URL, tmp); err != nil {
			_ = os.Remove(tmp)
			return err
		}
		if err := os.Rename(tmp, dest); err != nil {
			return err
		}
		return b.finalizeAsset(a, dest)
	}

	if b.Cfg.SeedDir != "" {
		seed := filepath.Join(b.Cfg.SeedDir, filepath.FromSlash(a.Path))
		if _, err := os.Stat(seed); err == nil {
			b.logf("seed %s ← %s", a.Path, seed)
			if err := os.MkdirAll(filepath.Dir(dest), 0o755); err != nil {
				return err
			}
			if err := copyFile(seed, dest); err != nil {
				return err
			}
			return b.finalizeAsset(a, dest)
		}
	}

	hint := "укажи url:/from: в configs/android-oem-hack.yaml или положи файл в " + b.Cfg.AssetsDir
	if b.Cfg.SeedDir != "" {
		hint += " / " + b.Cfg.SeedDir
	}
	return fmt.Errorf("нет %s — %s", dest, hint)
}

func (b *Job) downloadExtract(a *config.AssetSpec) error {
	dl := filepath.Join(b.Cfg.AssetsDir, ".dl")
	if err := os.MkdirAll(dl, 0o755); err != nil {
		return err
	}
	defer os.RemoveAll(dl)

	var archive string
	if a.From != "" {
		archive = b.asset(a.From)
		if _, err := os.Stat(archive); err != nil {
			return fmt.Errorf("from %s: %w", a.From, err)
		}
	} else {
		archive = filepath.Join(dl, "archive"+extFromURL(a.URL))
		if err := download(a.URL, archive); err != nil {
			return err
		}
	}

	extractDir := filepath.Join(dl, "x")
	if err := os.MkdirAll(extractDir, 0o755); err != nil {
		return err
	}
	if err := extractArchive(archive, extractDir); err != nil {
		return fmt.Errorf("extract %s: %w", archive, err)
	}

	src := filepath.Join(extractDir, filepath.FromSlash(a.Extract.Member))
	dest := b.asset(a.Path)
	if err := os.MkdirAll(filepath.Dir(dest), 0o755); err != nil {
		return err
	}
	if err := copyFile(src, dest); err != nil {
		return fmt.Errorf("extract %s: %w", a.Extract.Member, err)
	}
	for _, also := range a.Extract.Also {
		asrc := filepath.Join(extractDir, filepath.FromSlash(also.Member))
		adest := b.asset(also.Path)
		if _, err := os.Stat(asrc); err != nil {
			continue
		}
		if err := os.MkdirAll(filepath.Dir(adest), 0o755); err != nil {
			return err
		}
		if err := copyFile(asrc, adest); err != nil {
			return err
		}
		if a.Chmod != "" {
			_ = b.finalizeAsset(&config.AssetSpec{Chmod: a.Chmod}, adest)
		}
	}
	return nil
}

func extractArchive(archive, dest string) error {
	ext := strings.ToLower(filepath.Ext(archive))
	switch ext {
	case ".zip", ".apk", ".jar":
		cmd := exec.Command("unzip", "-qo", archive, "-d", dest)
		cmd.Stderr = os.Stderr
		return cmd.Run()
	case ".tgz", ".gz", ".tar":
		cmd := exec.Command("tar", "-xzf", archive, "-C", dest)
		cmd.Stderr = os.Stderr
		return cmd.Run()
	default:
		if err := exec.Command("unzip", "-qo", archive, "-d", dest).Run(); err == nil {
			return nil
		}
		cmd := exec.Command("tar", "-xzf", archive, "-C", dest)
		cmd.Stderr = os.Stderr
		return cmd.Run()
	}
}

func (b *Job) finalizeAsset(a *config.AssetSpec, dest string) error {
	if a.Chmod != "" {
		mode, err := strconv.ParseUint(a.Chmod, 8, 32)
		if err != nil {
			return fmt.Errorf("%s chmod %q: %w", a.Path, a.Chmod, err)
		}
		if err := os.Chmod(dest, os.FileMode(mode)); err != nil {
			return err
		}
	}
	if a.RequireARM && !fileIsARM(dest) {
		return fmt.Errorf("%s не ARM", a.Path)
	}
	return nil
}

func extFromURL(u string) string {
	base := filepath.Base(u)
	if filepath.Ext(base) != "" {
		return filepath.Ext(base)
	}
	return ".bin"
}

func download(url, dest string) error {
	cmd := exec.Command("curl", "-fsSL", "-L", "-o", dest, url)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

func stageCopyImages(b *Job) error {
	logoDst := filepath.Join(b.Cfg.OutDir, "logo.img")
	if b.Cfg.InstallLogo {
		neutral := b.asset("logo", "logo-neutral.img")
		if err := copyFile(neutral, logoDst); err != nil {
			return err
		}
		b.logf("logo: hisi (logo.enabled)")
	} else {
		if err := copyFile(b.part("logo.img"), logoDst); err != nil {
			return err
		}
		b.logf("logo: Cyta")
	}
	if err := copyFile(b.part("kernel.img"), filepath.Join(b.Cfg.OutDir, "kernel.img")); err != nil {
		return err
	}
	if err := copyFile(b.part("system.img"), b.Img); err != nil {
		return err
	}
	return nil
}
