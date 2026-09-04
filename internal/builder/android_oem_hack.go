package builder

import (
	"fmt"
	"path/filepath"

	"cytatv/internal/builder/logo"
	"cytatv/internal/builder/su"
	"cytatv/internal/config"
	"cytatv/internal/oemhack"
)

func oemhackFromConfig(cfg config.Config) oemhack.Config {
	a := cfg.AndroidOemHack
	apps := append([]oemhack.SystemAppSpec(nil), a.SystemApps...)
	return oemhack.Config{
		Root:                cfg.Root,
		OutDir:              a.OutputDir,
		AssetsDir:           a.AssetsDir,
		SeedDir:             a.SeedDir,
		PartitionsDir:       a.PartitionsDir,
		FilesystemDir:       a.FilesystemDir,
		Debugfs:             filepath.Join(a.E2fsSbin, "debugfs"),
		E2fsck:              filepath.Join(a.E2fsSbin, "e2fsck"),
		ServicesDockerImage: a.ServicesPatch.DockerImage,
		ServicesWorkDir:     a.ServicesPatch.WorkDir,
		ServicesAPI:         a.ServicesPatch.API,
		InstallSu:           a.Su.Enabled,
		InstallLogo:         a.Logo.Enabled,
		SystemApps:          apps,
		Assets:              a.Assets,
	}
}

// AndroidOemHack runs the Go oemhack pipeline.
func AndroidOemHack(cfg config.Config) error {
	a := cfg.AndroidOemHack
	if a.Su.Enabled {
		if err := su.Build(a.Su); err != nil {
			return err
		}
	}
	if a.Logo.Enabled {
		if err := logo.Build(a.Logo); err != nil {
			return err
		}
	}
	return oemhack.Run(oemhackFromConfig(cfg))
}

// Settings builds system_apps from config.
func Settings(cfg config.Config) error {
	fmt.Println("=== system_apps →", cfg.AndroidOemHack.AssetsDir, "===")
	return oemhack.BuildSystemApps(oemhackFromConfig(cfg))
}
