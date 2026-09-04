package oemhack

import (
	"fmt"
	"path/filepath"

	"cytatv/internal/config"
	"cytatv/internal/oemhack/logo"
	"cytatv/internal/oemhack/su"
)

func pipelineFromConfig(cfg config.Config) Config {
	a := cfg.AndroidOemHack
	apps := append([]config.SystemAppSpec(nil), a.SystemApps...)
	return Config{
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

// Build — android-oem-hack build (su/logo + pipeline).
func Build(cfg config.Config) error {
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
	return Run(pipelineFromConfig(cfg))
}

// Settings builds system_apps only.
func Settings(cfg config.Config) error {
	fmt.Println("=== system_apps →", cfg.AndroidOemHack.AssetsDir, "===")
	return BuildSystemApps(pipelineFromConfig(cfg))
}
