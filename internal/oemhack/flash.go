package oemhack

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"

	emmc "github.com/dimajolkin/eMMC153-Writer"

	"cytatv/internal/config"
)

var diskNameRE = regexp.MustCompile(`^disk[0-9]+$`)

// Flash — ISP Socket → logo+kernel+system (+userdata wipe).
func Flash(cfg config.Config) error {
	flash := cfg.AndroidOemHack.Flash
	if flash.Build {
		fmt.Println("=== flash.build → android-oem-hack build ===")
		if err := Build(cfg); err != nil {
			return err
		}
	}

	android := cfg.AndroidOemHack.OutputDir
	if android == "" {
		return fmt.Errorf("android_oem_hack.output_dir обязателен")
	}
	for _, name := range []string{"logo.img", "kernel.img", "system.img"} {
		p := filepath.Join(android, name)
		if _, err := os.Stat(p); err != nil {
			return fmt.Errorf("нет %s — сначала: q22e android-oem-hack build", p)
		}
	}

	fmt.Println("=== диски (Socket ~7.8G) ===")
	devs, err := emmc.ListExternalDevices()
	if err != nil {
		fmt.Printf("WARN: list devices: %v\n", err)
	} else {
		for _, d := range devs {
			fmt.Printf("  %s\n", d.Label())
		}
	}
	fmt.Println()

	disk := flash.Disk
	var device emmc.Device
	if disk == "" {
		device, err = emmc.FindSocketDevice()
		if err != nil {
			return fmt.Errorf("%w — укажи flash.disk или --disk diskN", err)
		}
		disk = device.ID
	} else {
		if !diskNameRE.MatchString(disk) {
			return fmt.Errorf("формат diskN, получено %q", disk)
		}
		if disk == "disk0" {
			return fmt.Errorf("disk0 запрещён")
		}
		device = emmc.Device{
			ID:      disk,
			Node:    "/dev/" + disk,
			RawNode: "/dev/r" + disk,
		}
		for _, d := range devs {
			if d.ID == disk {
				device = d
				break
			}
		}
	}

	fmt.Printf("Цель: %s  media=%q\n", device.RawNode, device.Name)
	fmt.Printf("Android: %s\n", android)
	if device.Name != "" && device.Name != "Socket" && !flash.Force {
		return fmt.Errorf("не Socket (media=%q) — flash.force: true или --force", device.Name)
	}

	if os.Geteuid() != 0 {
		return fmt.Errorf("нужен root: sudo go run ./cmd/q22e android-oem-hack flash -d %s --force\n(из Terminal.app с Full Disk Access)", disk)
	}

	fmt.Println()
	fmt.Println("=== eMMC153 BatchAndroid ===")
	err = emmc.BatchAndroid(emmc.AndroidBatch{
		DevicePath:   device.RawNode,
		AndroidDir:   android,
		Verify:       flash.Verify,
		WipeUserdata: flash.WipeUserdata,
	}, func(p emmc.Progress) {
		if p.Message != "" {
			fmt.Fprintf(os.Stderr, "[%s] %.1f%% %s\n", p.Phase, p.Percent, p.Message)
		} else {
			fmt.Fprintf(os.Stderr, "[%s] %.1f%%\n", p.Phase, p.Percent)
		}
	})
	if err != nil {
		return err
	}
	fmt.Println()
	fmt.Println("Готово. Чип → плата → питание. UART: go run ./cmd/q22e uart")
	return nil
}
