package config

import (
	"fmt"
	"path/filepath"
)

// Config — единый конфиг q22e (как reco-bills: агрегатор секций).
type Config struct {
	Root           string
	Ubuntu         Ubuntu
	AndroidOemHack AndroidOemHack
	Uart           Uart
	Original       Original
}

// Load читает configs/*.yaml относительно root.
// android-oem-hack.yaml мержится с опциональным android-oem-hack.local.yaml.
func Load(root string) (Config, error) {
	if root == "" {
		return Config{}, fmt.Errorf("root обязателен")
	}
	cfg := Config{Root: root}

	u, err := loadUbuntu(filepath.Join(root, "configs", "ubuntu.yaml"))
	if err != nil {
		return Config{}, err
	}
	cfg.Ubuntu = u

	aoh, err := loadAndroidOemHack(filepath.Join(root, "configs", "android-oem-hack.yaml"))
	if err != nil {
		return Config{}, err
	}
	cfg.AndroidOemHack = aoh

	uart, err := loadUart(filepath.Join(root, "configs", "uart.yaml"))
	if err != nil {
		return Config{}, err
	}
	cfg.Uart = uart

	orig, err := loadOriginal(filepath.Join(root, "configs", "original.yaml"))
	if err != nil {
		return Config{}, err
	}
	cfg.Original = orig

	if err := cfg.resolve(); err != nil {
		return Config{}, err
	}
	if err := cfg.validate(); err != nil {
		return Config{}, err
	}
	return cfg, nil
}

func (c *Config) resolve() error {
	r := c.Root
	c.Ubuntu.AuthorizedKeys = Abs(r, c.Ubuntu.AuthorizedKeys)
	c.Ubuntu.Output = Abs(r, c.Ubuntu.Output)

	c.AndroidOemHack.OutputDir = Abs(r, c.AndroidOemHack.OutputDir)
	c.AndroidOemHack.PartitionsDir = Abs(r, c.AndroidOemHack.PartitionsDir)
	c.AndroidOemHack.FilesystemDir = Abs(r, c.AndroidOemHack.FilesystemDir)
	c.AndroidOemHack.AssetsDir = Abs(r, c.AndroidOemHack.AssetsDir)
	c.AndroidOemHack.SeedDir = Abs(r, c.AndroidOemHack.SeedDir)
	c.AndroidOemHack.E2fsSbin = Abs(r, c.AndroidOemHack.E2fsSbin)
	c.AndroidOemHack.ServicesPatch.WorkDir = Abs(r, c.AndroidOemHack.ServicesPatch.WorkDir)

	c.AndroidOemHack.Su.OutDir = Abs(r, filepath.Join(c.AndroidOemHack.AssetsDir, "magisk-arm"))
	if c.AndroidOemHack.Logo.JPEG != "" {
		c.AndroidOemHack.Logo.JPEG = Abs(r, c.AndroidOemHack.Logo.JPEG)
	}
	c.AndroidOemHack.Logo.OutFile = Abs(r, filepath.Join(c.AndroidOemHack.AssetsDir, "logo", "logo-neutral.img"))

	for i := range c.AndroidOemHack.SystemApps {
		if c.AndroidOemHack.SystemApps[i].SrcDir != "" {
			c.AndroidOemHack.SystemApps[i].SrcDir = Abs(r, c.AndroidOemHack.SystemApps[i].SrcDir)
		}
	}

	if c.Uart.LogDir != "" {
		c.Uart.LogDir = Abs(r, c.Uart.LogDir)
	}

	c.Original.Dir = Abs(r, c.Original.Dir)
	c.Original.XML = Abs(r, c.Original.XML)
	if filepath.IsAbs(c.Original.Image) {
		// keep
	} else if c.Original.Image != "" {
		// leave relative name; ImagePath() joins with Dir
	}
	return nil
}

func (c Config) validate() error {
	if err := c.Ubuntu.Validate(); err != nil {
		return err
	}
	if err := c.AndroidOemHack.Validate(); err != nil {
		return err
	}
	if err := c.Uart.Validate(); err != nil {
		return err
	}
	if err := c.Original.Validate(); err != nil {
		return err
	}
	return nil
}
