package builder

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"strings"

	"cytatv/internal/config"
)

var diskNameRE = regexp.MustCompile(`^disk[0-9]+$`)

// UbuntuFlash пишет образ на SD/USB. imgOverride — аргумент CLI (пусто → cfg.Ubuntu.Output).
func UbuntuFlash(cfg config.Config, imgOverride string) error {
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
	fmt.Println("Доступные диски:")
	_ = run("", "sh", "-c", "diskutil list | grep -E '^/dev/disk|external|#:' || true")
	fmt.Println()

	flash := cfg.Ubuntu.Flash
	disk := flash.Disk
	force := flash.Force

	in := bufio.NewReader(os.Stdin)
	if disk == "" {
		fmt.Print("Введите diskN (например disk4, БЕЗ r): ")
		line, _ := in.ReadString('\n')
		disk = strings.TrimSpace(line)
	} else if !force {
		fmt.Printf("Подтвердите запись на %s (yes): ", disk)
		line, _ := in.ReadString('\n')
		if strings.TrimSpace(line) != "yes" {
			return fmt.Errorf("отменено")
		}
	}

	if !diskNameRE.MatchString(disk) {
		return fmt.Errorf("неверный формат: %q (ожидается diskN)", disk)
	}
	if err := assertSafeFlashDisk(disk); err != nil {
		return err
	}

	info, _ := exec.Command("diskutil", "info", "/dev/"+disk).CombinedOutput()
	media := awkField(string(info), "Device / Media Name")
	proto := awkField(string(info), "Protocol")
	fmt.Printf("Цель: /dev/%s  media=%q protocol=%q\n", disk, media, proto)
	fmt.Println("Будет записано — все данные на этом диске уничтожены!")

	if !force {
		fmt.Print("Подтвердите (yes): ")
		line, _ := in.ReadString('\n')
		if strings.TrimSpace(line) != "yes" {
			return fmt.Errorf("отменено")
		}
	}

	_ = exec.Command("diskutil", "unmountDisk", "/dev/"+disk).Run()

	rdev := "/dev/r" + disk
	fmt.Printf("dd → %s …\n", rdev)
	dd := exec.Command("sudo", "dd", "if="+img, "of="+rdev, "bs=4m", "status=progress")
	dd.Stdout = os.Stdout
	dd.Stderr = os.Stderr
	dd.Stdin = os.Stdin
	if err := dd.Run(); err != nil {
		return fmt.Errorf("dd: %w", err)
	}
	_ = exec.Command("sync").Run()
	_ = exec.Command("diskutil", "eject", "/dev/"+disk).Run()

	fmt.Println("Готово. Вставьте SD или USB (ehci) в STB до cold boot.")
	fmt.Println("  → cytatv-sd-linux: SSH root@Debian :22 + Enigma2 (Android на eMMC).")
	return nil
}

func assertSafeFlashDisk(disk string) error {
	if disk == "disk0" {
		return fmt.Errorf("отказ: disk0 — системный диск")
	}
	out, err := exec.Command("diskutil", "info", "/dev/"+disk).CombinedOutput()
	info := string(out)
	if err != nil {
		return fmt.Errorf("diskutil info /dev/%s: %w", disk, err)
	}
	lower := strings.ToLower(info)
	if strings.Contains(lower, "protocol:") && strings.Contains(lower, "apple fabric") {
		return fmt.Errorf("отказ: системный диск Mac (Apple Fabric)")
	}
	if strings.Contains(lower, "media name:") && strings.Contains(lower, "apple ssd") {
		return fmt.Errorf("отказ: системный диск Mac (APPLE SSD)")
	}
	internal := strings.Contains(lower, "device location:") && strings.Contains(lower, "internal")
	if internal {
		media := strings.ToLower(awkField(info, "Device / Media Name") + " " + awkField(info, "Protocol"))
		ok := strings.Contains(media, "secure digital") ||
			strings.Contains(media, "sdxc") ||
			strings.Contains(media, "sd card") ||
			strings.Contains(media, "card reader")
		if !ok {
			return fmt.Errorf("отказ: внутренний диск (не SD-ридер):\n%s", summarizeDiskInfo(info))
		}
	}
	return nil
}

func awkField(info, key string) string {
	for _, line := range strings.Split(info, "\n") {
		if !strings.Contains(line, key) {
			continue
		}
		parts := strings.SplitN(line, ":", 2)
		if len(parts) == 2 {
			return strings.TrimSpace(parts[1])
		}
	}
	return ""
}

func summarizeDiskInfo(info string) string {
	var lines []string
	for _, key := range []string{"Device Node", "Device / Media Name", "Protocol", "Device Location"} {
		if v := awkField(info, key); v != "" {
			lines = append(lines, "  "+key+": "+v)
		}
	}
	return strings.Join(lines, "\n")
}
