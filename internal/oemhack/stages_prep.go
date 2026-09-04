package oemhack

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
)

// AssetSpec describes one file needed by the pipeline (download / extract / seed).
type AssetSpec struct {
	Path       string        `yaml:"path"`
	URL        string        `yaml:"url"`
	Optional   bool          `yaml:"optional"`
	Chmod      string        `yaml:"chmod"` // e.g. "0755"
	RequireARM bool          `yaml:"require_arm"`
	Extract    *ExtractSpec  `yaml:"extract"`
}

// ExtractSpec unpacks an archive URL into path (+ optional siblings).
type ExtractSpec struct {
	Member string          `yaml:"member"` // path inside archive → AssetSpec.Path
	Also   []ExtractAlso   `yaml:"also"`
}

// ExtractAlso extracts an extra member to another path under assets_dir.
type ExtractAlso struct {
	Member string `yaml:"member"`
	Path   string `yaml:"path"`
}

func stageValidate(b *Build) error {
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

func stageFetchBins(b *Build) error {
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

func (b *Build) ensureAsset(a *AssetSpec) error {
	dest := b.asset(a.Path)
	if _, err := os.Stat(dest); err == nil {
		return b.finalizeAsset(a, dest)
	}

	if a.URL != "" {
		b.logf("download %s ← %s", a.Path, a.URL)
		if a.Extract != nil {
			if err := b.downloadExtract(a); err != nil {
				return err
			}
		} else {
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
		}
		return b.finalizeAsset(a, dest)
	}

	// seed from seed_dir
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

	hint := "укажи url: в configs/android-oem-hack.yaml или положи файл в " + b.Cfg.AssetsDir
	if b.Cfg.SeedDir != "" {
		hint += " / " + b.Cfg.SeedDir
	}
	return fmt.Errorf("нет %s — %s", dest, hint)
}

func (b *Build) downloadExtract(a *AssetSpec) error {
	dl := filepath.Join(b.Cfg.AssetsDir, ".dl")
	if err := os.MkdirAll(dl, 0o755); err != nil {
		return err
	}
	defer os.RemoveAll(dl)

	archive := filepath.Join(dl, "archive"+extFromURL(a.URL))
	if err := download(a.URL, archive); err != nil {
		return err
	}
	if err := exec.Command("tar", "-xzf", archive, "-C", dl).Run(); err != nil {
		return fmt.Errorf("tar extract %s: %w", a.URL, err)
	}

	src := filepath.Join(dl, filepath.FromSlash(a.Extract.Member))
	dest := b.asset(a.Path)
	if err := os.MkdirAll(filepath.Dir(dest), 0o755); err != nil {
		return err
	}
	if err := copyFile(src, dest); err != nil {
		return fmt.Errorf("extract %s: %w", a.Extract.Member, err)
	}
	for _, also := range a.Extract.Also {
		asrc := filepath.Join(dl, filepath.FromSlash(also.Member))
		adest := b.asset(also.Path)
		if _, err := os.Stat(asrc); err != nil {
			continue
		}
		if err := os.MkdirAll(filepath.Dir(adest), 0o755); err != nil {
			return err
		}
		_ = copyFile(asrc, adest)
	}
	return nil
}

func (b *Build) finalizeAsset(a *AssetSpec, dest string) error {
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
	cmd := exec.Command("curl", "-fsSL", "-o", dest, url)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

func stageCopyImages(b *Build) error {
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
