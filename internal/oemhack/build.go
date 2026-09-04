package oemhack

import (
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// SystemAppSpec — приложение для system uid (обычно 1000), собираемое из repo.
type SystemAppSpec struct {
	ID          string `yaml:"id"`
	UID         int    `yaml:"uid"`
	APK         string `yaml:"apk"`
	Guest       string `yaml:"guest"`
	RemoveStock string `yaml:"remove_stock"`
	SkipBuild   bool   `yaml:"skip_build"`
	Pull        bool   `yaml:"pull"`
	Repo        string `yaml:"repo"`
	Ref         string `yaml:"ref"`
	SrcDir      string `yaml:"src_dir"`
	MakeTarget  string `yaml:"make_target"`
}

// Config for android-oem-hack pipeline — все пути/значения задаются снаружи (yaml).
type Config struct {
	Root                string
	OutDir              string
	AssetsDir           string
	SeedDir             string
	PartitionsDir       string
	FilesystemDir       string
	Debugfs             string
	E2fsck              string
	ServicesDockerImage string
	ServicesWorkDir     string
	ServicesAPI         int
	InstallSu           bool // cytasu-daemon + su into system.img
	InstallLogo         bool // HiSi splash (logo-neutral.img) вместо Cyta
	SystemApps          []SystemAppSpec
	Assets              []AssetSpec
}

// Build holds mutable pipeline state. Methods with Build receiver live in this file.
type Build struct {
	Cfg     Config
	Img     string
	WorkDir string
	out     io.Writer
}

// NewBuild creates workdir. Required fields must already be set from config.
func NewBuild(cfg Config) (*Build, error) {
	if cfg.Root == "" {
		return nil, fmt.Errorf("Root required")
	}
	for _, f := range []struct {
		name, val string
	}{
		{"output_dir", cfg.OutDir},
		{"assets_dir", cfg.AssetsDir},
		{"seed_dir", cfg.SeedDir},
		{"partitions_dir", cfg.PartitionsDir},
		{"filesystem_dir", cfg.FilesystemDir},
		{"debugfs", cfg.Debugfs},
		{"e2fsck", cfg.E2fsck},
	} {
		if f.val == "" {
			return nil, fmt.Errorf("config: %s обязателен", f.name)
		}
	}
	if len(cfg.Assets) == 0 {
		return nil, fmt.Errorf("config: assets[] обязателен")
	}

	if err := os.MkdirAll(cfg.OutDir, 0o755); err != nil {
		return nil, err
	}
	wd, err := os.MkdirTemp("", "q22e-oemhack-*")
	if err != nil {
		return nil, err
	}
	return &Build{
		Cfg:     cfg,
		Img:     filepath.Join(cfg.OutDir, "system.img"),
		WorkDir: wd,
		out:     os.Stdout,
	}, nil
}

// Close removes the temp workdir.
func (b *Build) Close() {
	if b.WorkDir != "" {
		_ = os.RemoveAll(b.WorkDir)
	}
}

func (b *Build) logf(format string, args ...any) {
	fmt.Fprintf(b.out, format+"\n", args...)
}

func (b *Build) work(name string) string {
	return filepath.Join(b.WorkDir, name)
}

func (b *Build) asset(rel ...string) string {
	return filepath.Join(append([]string{b.Cfg.AssetsDir}, rel...)...)
}

func (b *Build) part(name string) string {
	return filepath.Join(b.Cfg.PartitionsDir, name)
}

// debugfsCmd runs debugfs; write=true adds -w.
func (b *Build) debugfsCmd(write bool, request string) error {
	args := []string{}
	if write {
		args = append(args, "-w")
	}
	args = append(args, "-R", request, b.Img)
	cmd := exec.Command(b.Cfg.Debugfs, args...)
	cmd.Stdout = nil
	cmd.Stderr = nil
	return cmd.Run()
}

// debugfsFile runs debugfs -w -f commandsFile.
func (b *Build) debugfsFile(commands string) error {
	f, err := os.CreateTemp(b.WorkDir, "dfs-*.cmd")
	if err != nil {
		return err
	}
	path := f.Name()
	if _, err := f.WriteString(commands); err != nil {
		f.Close()
		return err
	}
	f.Close()
	cmd := exec.Command(b.Cfg.Debugfs, "-w", "-f", path, b.Img)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("debugfs -f: %w\n%s", err, truncate(string(out), 500))
	}
	return nil
}

// Dump copies guest path to host file.
func (b *Build) Dump(guest, host string) error {
	return b.debugfsCmd(false, fmt.Sprintf("dump %s %s", guest, host))
}

// Rm removes guest path (ignore errors).
func (b *Build) Rm(guest string) {
	_ = b.debugfsCmd(true, "rm "+guest)
}

// Rmdir removes guest directory (ignore errors).
func (b *Build) Rmdir(guest string) {
	_ = b.debugfsCmd(true, "rmdir "+guest)
}

// RmTree best-effort recursive remove via "rm -r".
func (b *Build) RmTree(guest string) {
	_ = b.debugfsCmd(true, "rm -r "+guest)
}

// Mkdir creates guest directory (ignore errors).
func (b *Build) Mkdir(guest string) {
	_ = b.debugfsCmd(true, "mkdir "+guest)
}

// Stat checks guest path exists.
func (b *Build) Stat(guest string) bool {
	return b.debugfsCmd(false, "stat "+guest) == nil
}

// WriteBack writes host file into guest path; mode like "0100644" optional.
func (b *Build) WriteBack(host, guest, mode string) error {
	b.Rm(guest)
	if err := b.debugfsCmd(true, fmt.Sprintf("write %s %s", host, guest)); err != nil {
		return fmt.Errorf("write %s → %s: %w", host, guest, err)
	}
	if mode != "" {
		_ = b.debugfsCmd(true, fmt.Sprintf("set_inode_field %s mode %s", guest, mode))
	}
	return nil
}

// Cat runs debugfs cat and returns output.
func (b *Build) Cat(guest string) (string, error) {
	cmd := exec.Command(b.Cfg.Debugfs, "-R", "cat "+guest, b.Img)
	out, err := cmd.Output()
	return string(out), err
}

// Ls runs debugfs ls.
func (b *Build) Ls(guest string) (string, error) {
	cmd := exec.Command(b.Cfg.Debugfs, "-R", "ls "+guest, b.Img)
	out, err := cmd.CombinedOutput()
	return string(out), err
}

func truncate(s string, n int) string {
	s = strings.TrimSpace(s)
	if len(s) <= n {
		return s
	}
	return s[:n] + "…"
}

func mustExist(path string) error {
	if _, err := os.Stat(path); err != nil {
		return fmt.Errorf("нет %s", path)
	}
	return nil
}

func copyFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.OpenFile(dst, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o644)
	if err != nil {
		return err
	}
	defer out.Close()
	_, err = io.Copy(out, in)
	return err
}

func fileIsARM(path string) bool {
	out, err := exec.Command("file", path).Output()
	if err != nil {
		return false
	}
	return strings.Contains(string(out), "ARM")
}

func (b *Build) materializeScripts() error {
	entries, err := scriptFS.ReadDir("scripts")
	if err != nil {
		return err
	}
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		data, err := scriptFS.ReadFile("scripts/" + e.Name())
		if err != nil {
			return err
		}
		if err := os.WriteFile(b.work(e.Name()), data, 0o644); err != nil {
			return err
		}
	}
	return nil
}
