package oemhack

import (
	"os"
	"path/filepath"
	"testing"

	"cytatv/internal/config"
)

func TestResolveFileURL(t *testing.T) {
	root := "/Users/me/cytatv"
	got, err := resolveFileURL(root, "file://../q22e-android-settings/Settings.apk")
	if err != nil {
		t.Fatal(err)
	}
	want := "/Users/me/q22e-android-settings/Settings.apk"
	if got != want {
		t.Fatalf("got %q want %q", got, want)
	}
	got, err = resolveFileURL(root, "file:///tmp/Settings.apk")
	if err != nil {
		t.Fatal(err)
	}
	if got != "/tmp/Settings.apk" {
		t.Fatalf("abs: got %q", got)
	}
}

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

	// file:// Settings.apk — stub, если ещё не собирали.
	settingsSrc := filepath.Clean(filepath.Join(root, "../q22e-android-settings/Settings.apk"))
	if _, err := os.Stat(settingsSrc); err != nil {
		if err := os.WriteFile(settingsSrc, []byte("test-settings-apk"), 0o644); err != nil {
			t.Fatalf("stub Settings.apk: %v", err)
		}
		defer os.Remove(settingsSrc)
	}

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

	// file:// должен перезаписать assets даже если файл уже был.
	dest := filepath.Join(dir, "Settings.apk")
	if err := os.WriteFile(dest, []byte("old"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := stageFetchBins(b); err != nil {
		t.Fatal(err)
	}
	body, err := os.ReadFile(dest)
	if err != nil {
		t.Fatal(err)
	}
	if string(body) == "old" {
		t.Fatal("file:// Settings.apk не перезаписался")
	}
}
