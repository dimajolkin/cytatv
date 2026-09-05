package config

import (
	"fmt"
	"os"
	"path/filepath"

	"gopkg.in/yaml.v3"

	"cytatv/internal/oemhack/logo"
	"cytatv/internal/oemhack/su"
)

// ServicesPatch — baksmali/smali services.jar.
type ServicesPatch struct {
	DockerImage string `yaml:"docker_image"`
	WorkDir     string `yaml:"work_dir"`
	API         int    `yaml:"api"`
}

// AndroidOemHack — configs/android-oem-hack.yaml (+ optional .local.yaml).
type AndroidOemHack struct {
	OutputDir     string           `yaml:"output_dir"`
	PartitionsDir string           `yaml:"partitions_dir"`
	FilesystemDir string           `yaml:"filesystem_dir"`
	AssetsDir     string           `yaml:"assets_dir"`
	SeedDir       string           `yaml:"seed_dir"`
	E2fsSbin      string           `yaml:"e2fs_sbin"`
	ServicesPatch ServicesPatch    `yaml:"services_patch"`
	Su            su.Config        `yaml:"su"`
	Logo          logo.Config      `yaml:"logo"`
	SystemApps    []SystemAppSpec  `yaml:"system_apps"`
	InstallApps   []InstallAppSpec `yaml:"install_apps"`
	Launcher      LauncherSpec     `yaml:"launcher"`
	ReserveApps   []string         `yaml:"reserve_apps"`
	Assets        []AssetSpec      `yaml:"assets"`
	Flash         Flash            `yaml:"flash"`
}

func loadAndroidOemHack(path string) (AndroidOemHack, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return AndroidOemHack{}, err
	}
	localPath := filepath.Join(filepath.Dir(path), "android-oem-hack.local.yaml")
	if lb, err := os.ReadFile(localPath); err == nil {
		merged, err := mergeYAMLDocs(b, lb)
		if err != nil {
			return AndroidOemHack{}, fmt.Errorf("%s: %w", localPath, err)
		}
		b = merged
	} else if !os.IsNotExist(err) {
		return AndroidOemHack{}, fmt.Errorf("%s: %w", localPath, err)
	}
	var c AndroidOemHack
	if err := yaml.Unmarshal(b, &c); err != nil {
		return AndroidOemHack{}, fmt.Errorf("%s: %w", path, err)
	}
	return c, nil
}

// mergeYAMLDocs deep-merges overlay onto base.
// Maps merge recursively; scalars and sequences from overlay replace.
func mergeYAMLDocs(base, overlay []byte) ([]byte, error) {
	var bMap, oMap map[string]any
	if err := yaml.Unmarshal(base, &bMap); err != nil {
		return nil, fmt.Errorf("base: %w", err)
	}
	if err := yaml.Unmarshal(overlay, &oMap); err != nil {
		return nil, fmt.Errorf("overlay: %w", err)
	}
	if bMap == nil {
		bMap = map[string]any{}
	}
	merged := deepMergeMaps(bMap, oMap)
	out, err := yaml.Marshal(merged)
	if err != nil {
		return nil, err
	}
	return out, nil
}

func deepMergeMaps(dst, src map[string]any) map[string]any {
	for k, v := range src {
		if vMap, ok := asStringMap(v); ok {
			if dMap, ok := asStringMap(dst[k]); ok {
				dst[k] = deepMergeMaps(dMap, vMap)
				continue
			}
		}
		dst[k] = v
	}
	return dst
}

func asStringMap(v any) (map[string]any, bool) {
	switch m := v.(type) {
	case map[string]any:
		return m, true
	case map[any]any:
		out := make(map[string]any, len(m))
		for k, val := range m {
			ks, ok := k.(string)
			if !ok {
				return nil, false
			}
			out[ks] = val
		}
		return out, true
	default:
		return nil, false
	}
}

func (c AndroidOemHack) Validate() error {
	for _, f := range []struct {
		name, val string
	}{
		{"android_oem_hack.output_dir", c.OutputDir},
		{"android_oem_hack.partitions_dir", c.PartitionsDir},
		{"android_oem_hack.filesystem_dir", c.FilesystemDir},
		{"android_oem_hack.assets_dir", c.AssetsDir},
		{"android_oem_hack.e2fs_sbin", c.E2fsSbin},
		{"android_oem_hack.services_patch.docker_image", c.ServicesPatch.DockerImage},
		{"android_oem_hack.services_patch.work_dir", c.ServicesPatch.WorkDir},
	} {
		if f.val == "" {
			return errRequired(f.name)
		}
	}
	if c.ServicesPatch.API == 0 {
		return errRequired("android_oem_hack.services_patch.api")
	}
	if err := c.Su.Validate(); err != nil {
		return err
	}
	if err := c.Logo.Validate(); err != nil {
		return err
	}
	if len(c.Assets) == 0 {
		return errRequired("android_oem_hack.assets[]")
	}
	for i, app := range c.SystemApps {
		if app.ID == "" || app.APK == "" || app.Guest == "" {
			return fmt.Errorf("android_oem_hack.system_apps[%d]: id, apk, guest обязательны", i)
		}
		if app.UID == 0 {
			return fmt.Errorf("android_oem_hack.system_apps[%s]: uid обязателен", app.ID)
		}
		if !app.SkipBuild && app.Repo != "" {
			if app.Ref == "" || app.SrcDir == "" || app.MakeTarget == "" {
				return fmt.Errorf("android_oem_hack.system_apps[%s]: ref, src_dir, make_target обязательны при repo", app.ID)
			}
		}
	}
	for i, app := range c.InstallApps {
		if app.APK == "" || app.Guest == "" {
			return fmt.Errorf("android_oem_hack.install_apps[%d]: apk и guest обязательны", i)
		}
	}
	if c.Launcher.PreferredPkg == "" || c.Launcher.DefaultLauncher == "" {
		return errRequired("android_oem_hack.launcher.preferred_pkg / default_launcher")
	}
	if len(c.ReserveApps) == 0 {
		return errRequired("android_oem_hack.reserve_apps[]")
	}
	return nil
}
