package cli

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"cytatv/internal/config"
	"cytatv/internal/oemhack"
	"cytatv/internal/ubuntu"
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
		fmt.Println("(пусто — make apk-for-firmware в q22e-android-settings; go run ./cmd/q22e ubuntu|android-oem-hack build)")
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
	fmt.Println("  2) android-oem-hack  — build патченого OEM Android")
	fmt.Println("  3) all               — ubuntu + android-oem-hack")
	fmt.Println("  4) list")
	fmt.Print("> ")
	line, _ := in.ReadString('\n')
	line = strings.TrimSpace(line)
	switch line {
	case "1", "ubuntu", "u", "ubuntu build":
		return ubuntu.Build(cfg)
	case "2", "android-oem-hack", "aoh", "aoh build":
		return oemhack.Build(cfg)
	case "3", "all", "a":
		if err := ubuntu.Build(cfg); err != nil {
			return err
		}
		return oemhack.Build(cfg)
	case "4", "list", "l":
		return List(cfg)
	default:
		return fmt.Errorf("unknown choice %q", line)
	}
}
