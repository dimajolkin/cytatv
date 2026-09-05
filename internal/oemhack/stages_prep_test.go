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
	b, err := NewJob(pipe)
	if err != nil {
		t.Fatal(err)
	}
	defer b.Close()

	if err := stageFetchBins(b); err != nil {
		t.Fatal(err)
	}

	for _, a := range cfg.AndroidOemHack.Assets {
		if a.Optional {
			continue
		}
		if _, err := os.Stat(filepath.Join(dir, filepath.FromSlash(a.Path))); err != nil {
			t.Errorf("missing %s: %v", a.Path, err)
		}
	}
}
