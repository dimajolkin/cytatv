package original

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"cytatv/internal/config"
)

// Init проверяет дамп в build/original/, режет partitions и rdump filesystems.
func Init(cfg config.Config, force bool) error {
	o := cfg.Original
	if err := os.MkdirAll(o.Dir, 0o755); err != nil {
		return err
	}

	img, err := FindDump(o)
	if err != nil {
		return err
	}
	fmt.Println("=== original dump ===")
	fmt.Println(" ", img)

	parts, err := LoadParts(o.XML)
	if err != nil {
		return err
	}

	fmt.Println("=== partitions ===")
	if err := SlicePartitions(img, parts, o.PartitionsDir(), force); err != nil {
		return err
	}

	debugfs := filepath.Join(cfg.AndroidOemHack.E2fsSbin, "debugfs")
	fmt.Println("=== filesystems (debugfs) ===")
	if err := ExtractFilesystems(o, parts, debugfs, force); err != nil {
		return err
	}

	fmt.Println()
	fmt.Println("Готово:")
	fmt.Println(" ", o.PartitionsDir())
	fmt.Println(" ", o.FilesystemsDir())
	return nil
}

// FindDump ищет original.img / original.dmg или любой *.img/*.dmg в dir.
func FindDump(o config.Original) (string, error) {
	dir := o.Dir
	preferred := []string{
		o.ImagePath(),
		filepath.Join(dir, "original.img"),
		filepath.Join(dir, "original.dmg"),
		filepath.Join(dir, "emmc_full.img"),
		filepath.Join(dir, "eMMC153 Socket Media.dmg"),
	}
	seen := map[string]bool{}
	for _, p := range preferred {
		if p == "" || seen[p] {
			continue
		}
		seen[p] = true
		if st, err := os.Stat(p); err == nil && st.Size() > 0 {
			return p, nil
		}
	}

	entries, _ := os.ReadDir(dir)
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		name := e.Name()
		ext := strings.ToLower(filepath.Ext(name))
		if ext != ".img" && ext != ".dmg" {
			continue
		}
		p := filepath.Join(dir, name)
		if st, err := e.Info(); err == nil && st.Size() > 0 {
			return p, nil
		}
	}

	return "", missingDumpError(o)
}

func missingDumpError(o config.Original) error {
	return fmt.Errorf(`нет дампа в %s

Положи полный ISP-снимок eMMC (~7.3G) как:
  %s
  или %s/original.dmg
  (сырой .dmg с ридера — как «eMMC153 Socket Media.dmg» — тоже ок)

С Socket (Terminal.app + sudo + Full Disk Access):
  mkdir -p %s
  diskutil list   # Socket ~7.8G → rdiskN
  sudo dd if=/dev/rdiskN of=%s/original.img bs=4m status=progress

Потом снова: go run ./cmd/q22e init`,
		o.Dir,
		o.ImagePath(),
		o.Dir,
		o.Dir,
		o.Dir,
	)
}

// ExtractFilesystems — debugfs rdump для имён из config.filesystems.
func ExtractFilesystems(o config.Original, parts []Part, debugfs string, force bool) error {
	if _, err := os.Stat(debugfs); err != nil {
		return fmt.Errorf("%s — brew install e2fsprogs", debugfs)
	}
	want := map[string]bool{}
	for _, n := range o.Filesystems {
		want[strings.ToLower(n)] = true
	}
	fsRoot := o.FilesystemsDir()
	if err := os.MkdirAll(fsRoot, 0o755); err != nil {
		return err
	}

	byName := map[string]Part{}
	for _, p := range parts {
		byName[strings.ToLower(p.Name)] = p
	}

	for _, name := range o.Filesystems {
		p, ok := byName[strings.ToLower(name)]
		if !ok {
			return fmt.Errorf("filesystem %q нет в XML", name)
		}
		img := filepath.Join(o.PartitionsDir(), p.Name+".img")
		if _, err := os.Stat(img); err != nil {
			return fmt.Errorf("нет %s — сначала partitions", img)
		}
		out := filepath.Join(fsRoot, p.Name)
		marker := filepath.Join(out, ".q22e-extracted")
		if !force {
			if _, err := os.Stat(marker); err == nil {
				fmt.Printf("  OK  filesystems/%s\n", p.Name)
				continue
			}
		}
		_ = os.RemoveAll(out)
		if err := os.MkdirAll(out, 0o755); err != nil {
			return err
		}
		fmt.Printf("  →  rdump %s → filesystems/%s\n", p.Name+".img", p.Name)
		// ownership errors на macOS нормальны — файлы всё равно пишутся
		cmd := exec.Command(debugfs, "-R", "rdump / "+out, img)
		cmd.Stderr = os.Stderr
		_ = cmd.Run()
		if err := os.WriteFile(marker, []byte(p.Name+"\n"), 0o644); err != nil {
			return err
		}
	}
	return nil
}
