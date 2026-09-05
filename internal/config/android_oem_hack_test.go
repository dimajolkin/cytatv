package config

import (
	"os"
	"path/filepath"
	"testing"

	yaml "go.yaml.in/yaml/v4"
)

func TestMergeYAMLDocs(t *testing.T) {
	base := []byte(`
output_dir: build/a
flash:
  disk: ""
  force: false
  verify: false
assets:
  - path: a.apk
`)
	overlay := []byte(`
flash:
  disk: disk4
  force: true
su:
  enabled: false
`)
	merged, err := mergeYAMLDocs(base, overlay)
	if err != nil {
		t.Fatal(err)
	}
	var c AndroidOemHack
	if err := yaml.Unmarshal(merged, &c); err != nil {
		t.Fatal(err)
	}
	if c.OutputDir != "build/a" {
		t.Fatalf("output_dir: %q", c.OutputDir)
	}
	if c.Flash.Disk != "disk4" || !c.Flash.Force {
		t.Fatalf("flash: %+v", c.Flash)
	}
	if len(c.Assets) != 1 || c.Assets[0].Path != "a.apk" {
		t.Fatalf("assets should stay from base: %+v", c.Assets)
	}
}

func TestLoadAndroidOemHackLocal(t *testing.T) {
	dir := t.TempDir()
	base := filepath.Join(dir, "android-oem-hack.yaml")
	local := filepath.Join(dir, "android-oem-hack.local.yaml")
	if err := os.WriteFile(base, []byte(`
output_dir: build/android-oem-hack
partitions_dir: build/original/partitions
filesystem_dir: build/original/filesystems/system
assets_dir: build/android-oem-hack/assets
seed_dir: assets
e2fs_sbin: /opt/homebrew/opt/e2fsprogs/sbin
services_patch:
  docker_image: cytatv-android:dev
  work_dir: build/android-oem-hack/work/services
  api: 24
su:
  enabled: false
  ndk: /tmp/ndk
  api: 21
  host_tag: darwin-x86_64
  target: armv7a-linux-androideabi
logo:
  enabled: false
  jpeg: assets/logo/neutral.jpg
  size_mib: 16
flash:
  disk: ""
  force: false
system_apps:
  - id: settings
    uid: 1000
    apk: Settings.apk
    guest: /priv-app/Settings/Settings.apk
launcher:
  preferred_pkg: com.benny.openlauncher
  default_launcher: com.benny.openlauncher
reserve_apps:
  - system
assets:
  - path: Settings.apk
`), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(local, []byte(`
flash:
  disk: disk9
  force: true
`), 0o644); err != nil {
		t.Fatal(err)
	}

	c, err := loadAndroidOemHack(base)
	if err != nil {
		t.Fatal(err)
	}
	if c.Flash.Disk != "disk9" || !c.Flash.Force {
		t.Fatalf("local merge failed: %+v", c.Flash)
	}
	if c.OutputDir != "build/android-oem-hack" {
		t.Fatalf("base lost: %q", c.OutputDir)
	}
}

func TestLoadAndroidOemHackWithoutLocal(t *testing.T) {
	dir := t.TempDir()
	base := filepath.Join(dir, "android-oem-hack.yaml")
	if err := os.WriteFile(base, []byte(`
output_dir: build/x
flash:
  disk: disk1
`), 0o644); err != nil {
		t.Fatal(err)
	}
	c, err := loadAndroidOemHack(base)
	if err != nil {
		t.Fatal(err)
	}
	if c.OutputDir != "build/x" || c.Flash.Disk != "disk1" {
		t.Fatalf("%+v", c)
	}
}
