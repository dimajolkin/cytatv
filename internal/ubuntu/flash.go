package ubuntu

import (
	"fmt"
	"os"
	"os/exec"

	"cytatv/internal/config"
	"cytatv/internal/flash"
)

// Flash пишет образ на SD/USB. imgOverride — аргумент CLI (пусто → cfg.Ubuntu.Output).
func Flash(cfg config.Config, imgOverride string) error {
	img := imgOverride
	if img == "" {
		img = cfg.Ubuntu.Output
	} else {
		img = config.Abs(cfg.Root, img)
	}
	if img == "" {
		return fmt.Errorf("нужен путь к образу: аргумент или ubuntu.output в yaml")
	}
	if !fileExists(img) {
		return fmt.Errorf("нет образа %s — сначала: q22e ubuntu build", img)
	}

	st, err := os.Stat(img)
	if err != nil {
		return err
	}
	fmt.Println("=== Запись Ubuntu chroot на SD/USB ===")
	fmt.Printf("Образ: %s (%s)\n\n", img, humanSize(st.Size()))
	if err := flash.PrintCandidates(); err != nil {
		return err
	}
	fmt.Println()

	opts := cfg.Ubuntu.Flash
	disk, err := flash.ResolveDisk(opts.Disk, opts.Force)
	if err != nil {
		return err
	}

	media, proto, _ := flash.Info(disk)
	fmt.Printf("Цель: %s  media=%q protocol=%q\n", flash.DevPath(disk), media, proto)
	fmt.Println("Будет записано — все данные на этом диске уничтожены!")
	if err := flash.ConfirmYes("Подтвердите (yes): ", opts.Force); err != nil {
		return err
	}

	flash.UnmountDisk(disk)

	rdev := flash.RawPath(disk)
	fmt.Printf("dd → %s …\n", rdev)
	if err := flash.Sudo("dd", "if="+img, "of="+rdev, "bs=4m", "status=progress"); err != nil {
		return err
	}
	_ = exec.Command("sync").Run()
	flash.Eject(disk)

	fmt.Println("Готово. Вставьте SD или USB (ehci) в STB до cold boot.")
	fmt.Println("  → cytatv-sd-linux: SSH root@Debian :22 + Enigma2 (Android на eMMC).")
	return nil
}

func humanSize(n int64) string {
	const mb = 1024 * 1024
	if n >= mb {
		return fmt.Sprintf("%.1fM", float64(n)/float64(mb))
	}
	return fmt.Sprintf("%dB", n)
}
