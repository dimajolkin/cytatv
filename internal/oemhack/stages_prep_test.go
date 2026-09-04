package oemhack

import (
	"os"
	"path/filepath"
	"testing"

	"cytatv/internal/config"
)

func TestFetchAssetsFromURLs(t *testing.T) {
	root, err := filepath.Abs("../..")
	if err != nil {
		t.Fatal(err)
	}
	cfg, err := config.Load(root)
	if err != nil {
		t.Fatal(err)
	}
	dir := t.TempDir()
	cfg.AndroidOemHack.AssetsDir = dir
	cfg.AndroidOemHack.SeedDir = filepath.Join(root, "assets")

	pipe := pipelineFromConfig(cfg)
	pipe.AssetsDir = dir
	pipe.SeedDir = filepath.Join(root, "assets")
	// skip su/logo outputs requirement for this test
	b, err := NewJob(pipe)
	if err != nil {
		t.Fatal(err)
	}
	defer b.Close()

	if err := stageFetchBins(b); err != nil {
		t.Fatal(err)
	}

	for _, p := range []string{
		"Lawnchair.apk",
		"Magisk.apk",
		"magisk-arm/magisk",
		"magisk-arm/magiskpolicy",
		"magisk-arm/busybox",
		"dropbear-arm/dropbear",
		"dropbear-arm/dropbearkey",
		"dropbear-arm/scp",
		"ssh/authorized_keys",
		"extras/TermOnePlus.apk",
		"extras/Lightning.apk",
		"bash-arm/bash",
		"adbd-arm/adbd",
		"logo/neutral.jpg",
	} {
		if _, err := os.Stat(filepath.Join(dir, filepath.FromSlash(p))); err != nil {
			t.Errorf("missing %s: %v", p, err)
		}
	}
}
