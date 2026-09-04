package su

import (
	"embed"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
)

//go:embed src/daemon.c src/su.c
var srcFS embed.FS

// Config for NDK build of cytasu-daemon + su.
type Config struct {
	Enabled bool   `yaml:"enabled"`
	NDK     string `yaml:"ndk"`
	API     int    `yaml:"api"`
	HostTag string `yaml:"host_tag"`
	Target  string `yaml:"target"`
	OutDir  string // absolute, set by caller (assets/magisk-arm)
}

// Validate checks fields when Enabled.
func (c Config) Validate() error {
	if !c.Enabled {
		return nil
	}
	for _, f := range []struct {
		name, val string
	}{
		{"su.ndk", c.NDK},
		{"su.host_tag", c.HostTag},
		{"su.target", c.Target},
		{"su out_dir", c.OutDir},
	} {
		if f.val == "" {
			return fmt.Errorf("%s обязателен при su.enabled", f.name)
		}
	}
	if c.API == 0 {
		return fmt.Errorf("su.api обязателен при su.enabled")
	}
	return nil
}

// Build compiles cytasu-daemon + su (static ARM) into cfg.OutDir.
func Build(cfg Config) error {
	if err := cfg.Validate(); err != nil {
		return err
	}
	if !cfg.Enabled {
		return nil
	}
	if err := os.MkdirAll(cfg.OutDir, 0o755); err != nil {
		return err
	}

	prebuilt := filepath.Join(cfg.NDK, "toolchains", "llvm", "prebuilt", cfg.HostTag, "bin")
	clang := filepath.Join(prebuilt, fmt.Sprintf("%s%d-clang", cfg.Target, cfg.API))
	strip := filepath.Join(prebuilt, "llvm-strip")
	for _, p := range []string{clang, strip} {
		if _, err := os.Stat(p); err != nil {
			return fmt.Errorf("нет %s — проверь su.ndk/host_tag/target/api в android-oem-hack.yaml", p)
		}
	}

	work, err := os.MkdirTemp("", "q22e-su-*")
	if err != nil {
		return err
	}
	defer os.RemoveAll(work)

	for _, name := range []string{"src/daemon.c", "src/su.c"} {
		data, err := srcFS.ReadFile(name)
		if err != nil {
			return err
		}
		if err := os.WriteFile(filepath.Join(work, filepath.Base(name)), data, 0o644); err != nil {
			return err
		}
	}

	daemonOut := filepath.Join(cfg.OutDir, "cytasu-daemon")
	suOut := filepath.Join(cfg.OutDir, "su")

	fmt.Println("=== cytasu-daemon (NDK static ARM) ===")
	if err := run(clang, "-O2", "-static", "-o", daemonOut, filepath.Join(work, "daemon.c")); err != nil {
		return err
	}
	fmt.Println("=== su client ===")
	if err := run(clang, "-O2", "-static", "-o", suOut, filepath.Join(work, "su.c")); err != nil {
		return err
	}
	if err := run(strip, daemonOut, suOut); err != nil {
		return err
	}
	for _, p := range []string{daemonOut, suOut} {
		st, err := os.Stat(p)
		if err != nil {
			return err
		}
		fmt.Printf("  %s %d\n", p, st.Size())
	}
	return nil
}

func run(name string, args ...string) error {
	cmd := exec.Command(name, args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}
