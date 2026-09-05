package oemhack

import (
	"fmt"
	"os"
	"path/filepath"

	emmc "github.com/dimajolkin/eMMC153-Writer"

	"cytatv/internal/config"
	"cytatv/internal/flash"
)

// Flash — ISP Socket → logo+kernel+system (+userdata wipe).
func Flash(cfg config.Config) error {
	opts := cfg.AndroidOemHack.Flash
	if opts.Build {
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
	if err := flash.PrintCandidates(); err != nil {
		fmt.Printf("WARN: list devices: %v\n", err)
	}
	fmt.Println()

	disk := opts.Disk
	var device emmc.Device
	devs, _ := emmc.ListExternalDevices()
	if disk == "" {
		var err error
		device, err = emmc.FindSocketDevice()
		if err != nil {
			return fmt.Errorf("%w — укажи flash.disk или --disk diskN", err)
		}
		disk = device.ID
		fmt.Printf("Авто: %s\n", device.Label())
	} else {
		if err := flash.ValidateName(disk); err != nil {
			return err
		}
		device = emmc.Device{
			ID:      disk,
			Node:    flash.DevPath(disk),
			RawNode: flash.RawPath(disk),
		}
		for _, d := range devs {
			if d.ID == disk {
				device = d
				break
			}
		}
	}

	if err := flash.AssertSafe(disk); err != nil {
		return err
	}

	fmt.Printf("Цель: %s  media=%q\n", device.RawNode, device.Name)
	fmt.Printf("Android: %s\n", android)
	if device.Name != "" && device.Name != "Socket" && !opts.Force {
		return fmt.Errorf("не Socket (media=%q) — flash.force: true или --force", device.Name)
	}
	fmt.Println("Будет записано — разделы logo/kernel/system (+userdata wipe)!")
	if err := flash.ConfirmYes("Подтвердите (yes): ", opts.Force); err != nil {
		return err
	}

	// Как ubuntu dd: sudo запрашивается здесь, не требует запуска всей команды от root.
	if err := flash.Elevate([]string{"-d", disk, "--force"}, []string{"--build"}); err != nil {
		return err
	}

	fmt.Println()
	fmt.Println("=== eMMC153 BatchAndroid ===")
	err := emmc.BatchAndroid(emmc.AndroidBatch{
		DevicePath:   device.RawNode,
		AndroidDir:   android,
		Verify:       opts.Verify,
		WipeUserdata: opts.WipeUserdata,
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
