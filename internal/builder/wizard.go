package builder

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"cytatv/internal/config"
)

func List(cfg config.Config) error {
	build := filepath.Join(cfg.Root, "build")
	entries := []string{
		"ubuntu/ubuntu-chroot.img",
		"android-oem-hack/system.img",
		"android-oem-hack/kernel.img",
		"android-oem-hack/logo.img",
	}
	fmt.Println("build/ artifacts:")
	any := false
	for _, rel := range entries {
		p := filepath.Join(build, rel)
		if st, err := os.Stat(p); err == nil {
			fmt.Printf("  OK  %-40s %s\n", rel, humanSize(st.Size()))
			any = true
		} else {
			fmt.Printf("  --  %s\n", rel)
		}
	}
	apk := filepath.Join(cfg.AndroidOemHack.AssetsDir, "Settings.apk")
	if st, err := os.Stat(apk); err == nil {
		fmt.Printf("  OK  %-40s %s\n", "assets/Settings.apk", humanSize(st.Size()))
		any = true
	} else {
		fmt.Printf("  --  assets/Settings.apk\n")
	}
	if !any {
		fmt.Println("(пусто — go run ./cmd/q22e ubuntu build | settings | android-oem-hack build)")
	}
	return nil
}

func humanSize(n int64) string {
	const mb = 1024 * 1024
	if n >= mb {
		return fmt.Sprintf("%.1fM", float64(n)/float64(mb))
	}
	return fmt.Sprintf("%dB", n)
}

// Wizard interactive build picker.
func Wizard(cfg config.Config) error {
	in := bufio.NewReader(os.Stdin)
	fmt.Println("q22e builder — что собрать?")
	fmt.Println("  1) ubuntu build      — Ubuntu Base chroot image")
	fmt.Println("  2) settings          — system_apps (uid=1000) из конфига")
	fmt.Println("  3) android-oem-hack  — build патченого OEM Android")
	fmt.Println("  4) settings + aoh build")
	fmt.Println("  5) all               — ubuntu build + settings + aoh build")
	fmt.Println("  6) list")
	fmt.Print("> ")
	line, _ := in.ReadString('\n')
	line = strings.TrimSpace(line)
	switch line {
	case "1", "ubuntu", "u", "ubuntu build":
		return Ubuntu(cfg)
	case "2", "settings", "s":
		return Settings(cfg)
	case "3", "android-oem-hack", "aoh", "aoh build":
		return AndroidOemHack(cfg)
	case "4", "sa", "settings+aoh":
		if err := Settings(cfg); err != nil {
			return err
		}
		return AndroidOemHack(cfg)
	case "5", "all", "a":
		if err := Ubuntu(cfg); err != nil {
			return err
		}
		if err := Settings(cfg); err != nil {
			return err
		}
		return AndroidOemHack(cfg)
	case "6", "list", "l":
		return List(cfg)
	default:
		return fmt.Errorf("unknown choice %q", line)
	}
}
