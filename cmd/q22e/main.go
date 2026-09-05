package main

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"

	"cytatv/internal/cli"
	"cytatv/internal/config"
	"cytatv/internal/oemhack"
	"cytatv/internal/original"
	"cytatv/internal/ubuntu"
)

func main() {
	rootCmd := &cobra.Command{
		Use:           "q22e",
		Short:         "Q22E firmware build CLI",
		Long:          "Сборка Ubuntu chroot, Settings и android-oem-hack для Huawei Q22E (Hi3798CV200).",
		SilenceUsage:  true,
		SilenceErrors: true,
	}

	rootCmd.AddCommand(
		cmd("wizard", []string{"w"}, "Интерактивный выбор сборки", cli.Wizard),
		initCmd(),
		keysCmd(),
		ubuntuCmd(),
		cmd("settings", []string{"s"}, "system_apps из конфига (repo → apk)", oemhack.Settings),
		androidOemHackCmd(),
		cmd("list", []string{"ls", "l"}, "Показать артефакты в build/", cli.List),
		uartCmd(),
	)

	if err := rootCmd.Execute(); err != nil {
		fmt.Fprintf(os.Stderr, "q22e: %v\n", err)
		os.Exit(1)
	}
}

func loadConfig() (config.Config, error) {
	root, err := cli.Root()
	if err != nil {
		return config.Config{}, err
	}
	return config.Load(root)
}

func withConfig(fn func(config.Config) error) func(*cobra.Command, []string) error {
	return func(_ *cobra.Command, _ []string) error {
		cfg, err := loadConfig()
		if err != nil {
			return err
		}
		return fn(cfg)
	}
}

func cmd(use string, aliases []string, short string, fn func(config.Config) error) *cobra.Command {
	return &cobra.Command{
		Use:     use,
		Aliases: aliases,
		Short:   short,
		RunE:    withConfig(fn),
	}
}

func initCmd() *cobra.Command {
	var force bool
	c := &cobra.Command{
		Use:   "init",
		Short: "Дамп original.img|.dmg → partitions + filesystems",
		Long:  "Ищет build/original/original.img или .dmg (сырой ISP-дамп), режет разделы и rdump system/userdata.",
		RunE: func(cmd *cobra.Command, _ []string) error {
			cfg, err := loadConfig()
			if err != nil {
				return err
			}
			return original.Init(cfg, force)
		},
	}
	c.Flags().BoolVar(&force, "force", false, "пересобрать partitions/filesystems")
	return c
}

func keysCmd() *cobra.Command {
	var force bool
	c := &cobra.Command{
		Use:     "keys",
		Aliases: []string{"ssh-keys"},
		Short:   "Сгенерировать SSH ed25519 → assets/ssh/",
		RunE: func(cmd *cobra.Command, _ []string) error {
			cfg, err := loadConfig()
			if err != nil {
				return err
			}
			return cli.GenerateSSHKeys(cfg, force)
		},
	}
	c.Flags().BoolVar(&force, "force", false, "перезаписать существующие ключи")
	return c
}

func ubuntuCmd() *cobra.Command {
	c := &cobra.Command{
		Use:     "ubuntu",
		Aliases: []string{"u"},
		Short:   "Ubuntu chroot: build | flash",
	}
	c.AddCommand(
		&cobra.Command{
			Use:     "build",
			Aliases: []string{"b"},
			Short:   "Ubuntu Base → build/ubuntu/ubuntu-chroot.img",
			RunE:    withConfig(ubuntu.Build),
		},
		ubuntuFlashCmd(),
	)
	return c
}

func ubuntuFlashCmd() *cobra.Command {
	var disk string
	var force bool
	c := &cobra.Command{
		Use:     "flash [image.img]",
		Aliases: []string{"f"},
		Short:   "Записать ubuntu-chroot.img на SD/USB (dd)",
		Args:    cobra.MaximumNArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			cfg, err := loadConfig()
			if err != nil {
				return err
			}
			if cmd.Flags().Changed("disk") {
				cfg.Ubuntu.Flash.Disk = disk
			}
			if cmd.Flags().Changed("force") {
				cfg.Ubuntu.Flash.Force = force
			}
			img := ""
			if len(args) > 0 {
				img = args[0]
			}
			return ubuntu.Flash(cfg, img)
		},
	}
	c.Flags().StringVarP(&disk, "disk", "d", "", "цель diskN (или ubuntu.flash.disk в yaml)")
	c.Flags().BoolVar(&force, "force", false, "без подтверждения (или ubuntu.flash.force)")
	return c
}

func androidOemHackCmd() *cobra.Command {
	c := &cobra.Command{
		Use:     "android-oem-hack",
		Aliases: []string{"aoh"},
		Short:   "OEM Android: build | test | flash (ISP eMMC)",
	}
	c.AddCommand(
		&cobra.Command{
			Use:     "build",
			Aliases: []string{"b"},
			Short:   "Патч system → build/android-oem-hack/",
			RunE:    withConfig(oemhack.Build),
		},
		&cobra.Command{
			Use:     "test",
			Aliases: []string{"t"},
			Short:   "Проверить system.img против yaml (debugfs)",
			RunE:    withConfig(oemhack.Test),
		},
		aohFlashCmd(),
	)
	return c
}

func aohFlashCmd() *cobra.Command {
	var disk string
	var force, verify, buildFirst bool
	c := &cobra.Command{
		Use:     "flash",
		Aliases: []string{"f"},
		Short:   "ISP Socket → eMMC153 (logo+kernel+system)",
		RunE: func(cmd *cobra.Command, _ []string) error {
			cfg, err := loadConfig()
			if err != nil {
				return err
			}
			f := &cfg.AndroidOemHack.Flash
			if cmd.Flags().Changed("disk") {
				f.Disk = disk
			}
			if cmd.Flags().Changed("force") {
				f.Force = force
			}
			if cmd.Flags().Changed("verify") {
				f.Verify = verify
			}
			if cmd.Flags().Changed("build") {
				f.Build = buildFirst
			}
			return oemhack.Flash(cfg)
		},
	}
	c.Flags().StringVarP(&disk, "disk", "d", "", "цель diskN (или flash.disk); иначе автопоиск Socket")
	c.Flags().BoolVar(&force, "force", false, "писать даже если media ≠ Socket (или flash.force)")
	c.Flags().BoolVar(&verify, "verify", false, "verify после записи (или flash.verify)")
	c.Flags().BoolVar(&buildFirst, "build", false, "сначала android-oem-hack build (или flash.build)")
	return c
}

func uartCmd() *cobra.Command {
	var baud int
	c := &cobra.Command{
		Use:     "uart [port]",
		Aliases: []string{"serial"},
		Short:   "Захват UART boot-лога → log_dir/boot-log-*.txt (Ctrl+C стоп)",
		Args:    cobra.MaximumNArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			cfg, err := loadConfig()
			if err != nil {
				return err
			}
			if cmd.Flags().Changed("baud") {
				cfg.Uart.Baud = baud
			}
			port := ""
			if len(args) > 0 {
				port = args[0]
			}
			return cli.UartCapture(cfg, port)
		},
	}
	c.Flags().IntVarP(&baud, "baud", "b", 115200, "скорость (или uart.baud в yaml)")
	return c
}
