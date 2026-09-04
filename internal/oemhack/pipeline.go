package oemhack

import (
	"fmt"
)

// Stage is one named pipeline step.
type Stage struct {
	Name string
	Run  func(*Job) error
}

// DefaultStages returns the full android-oem-hack pipeline.
func DefaultStages() []Stage {
	return []Stage{
		{"validate", stageValidate},
		{"fetchAssets", stageFetchBins},
		{"systemApps", stageSystemApps},
		{"copyImages", stageCopyImages},
		{"stripOperator", stageStripOperator},
		{"patchPropsAndScripts", stagePatchPropsAndScripts},
		{"writeInitAndHooks", stageWriteInitAndHooks},
		{"wifiCalFirmware", stageWifiCalFirmware},
		{"installApps", stageInstallApps},
		{"installRootTools", stageInstallRootTools},
		{"e2fsck", stageE2fsck},
		{"manifest", stageManifest},
	}
}

// Run executes stages in order.
func Run(cfg Config) error {
	b, err := NewJob(cfg)
	if err != nil {
		return err
	}
	defer b.Close()

	b.logf("=== android-oem-hack → %s ===", b.Cfg.OutDir)
	for _, st := range DefaultStages() {
		b.logf("=== %s ===", st.Name)
		if err := st.Run(b); err != nil {
			return fmt.Errorf("%s: %w", st.Name, err)
		}
	}
	b.logf("")
	b.logf("Done: %s", b.Cfg.OutDir)
	return nil
}
