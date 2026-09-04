package oemhack

import (
	"archive/zip"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// PatchServicesJar deodexes services.odex, mocks compareSignatures* → MATCH (0), writes assets/services.jar.
func (b *Build) PatchServicesJar() error {
	if b.Cfg.ServicesDockerImage == "" || b.Cfg.ServicesWorkDir == "" {
		return fmt.Errorf("services_patch.docker_image и work_dir обязательны")
	}
	fw := filepath.Join(b.Cfg.FilesystemDir, "framework")
	odex := filepath.Join(fw, "oat", "arm", "services.odex")
	boot := filepath.Join(fw, "arm", "boot.oat")
	srcJar := filepath.Join(fw, "services.jar")
	for _, p := range []string{odex, boot, srcJar} {
		if err := mustExist(p); err != nil {
			return err
		}
	}

	work := b.Cfg.ServicesWorkDir
	smaliDir := filepath.Join(work, "smali")
	dexPath := filepath.Join(work, "classes.dex")
	out := b.asset("services.jar")

	if err := os.RemoveAll(smaliDir); err != nil {
		return err
	}
	if err := os.MkdirAll(work, 0o755); err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(out), 0o755); err != nil {
		return err
	}

	api := b.Cfg.ServicesAPI
	if api == 0 {
		return fmt.Errorf("services_patch.api обязателен")
	}

	b.logf("=== baksmali deodex services.odex (%s) ===", b.Cfg.ServicesDockerImage)
	if err := dockerRun(b.Cfg.ServicesDockerImage, []string{
		"-v", fw + ":/fw:ro",
		"-v", work + ":/work",
	}, []string{
		"baksmali", "deodex",
		"-a", fmt.Sprintf("%d", api),
		"-b", "/fw/arm/boot.oat",
		"-o", "/work/smali",
		"/fw/oat/arm/services.odex",
	}); err != nil {
		return err
	}

	pms := filepath.Join(smaliDir, "com", "android", "server", "pm", "PackageManagerService.smali")
	if err := mustExist(pms); err != nil {
		return err
	}
	if err := patchPackageManagerSignatures(pms); err != nil {
		return err
	}
	b.logf("patched compareSignatures* → always SIGNATURE_MATCH")

	b.logf("=== smali assemble ===")
	if err := dockerRun(b.Cfg.ServicesDockerImage, []string{
		"-v", work + ":/work",
	}, []string{
		"smali", "assemble",
		"-a", fmt.Sprintf("%d", api),
		"-o", "/work/classes.dex",
		"/work/smali",
	}); err != nil {
		return err
	}
	st, err := os.Stat(dexPath)
	if err != nil || st.Size() == 0 {
		return fmt.Errorf("пустой classes.dex")
	}

	b.logf("=== services.jar + classes.dex ===")
	if err := copyFile(srcJar, out); err != nil {
		return err
	}
	if err := injectDexIntoJar(out, dexPath); err != nil {
		return err
	}
	b.logf("OK: %s (dex %d bytes)", out, st.Size())
	return nil
}

func dockerRun(image string, mounts []string, args []string) error {
	cmdArgs := append([]string{"run", "--rm"}, mounts...)
	cmdArgs = append(cmdArgs, image)
	cmdArgs = append(cmdArgs, args...)
	cmd := exec.Command("docker", cmdArgs...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

func patchPackageManagerSignatures(path string) error {
	data, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	text := string(data)
	stub := "    .registers 16\n    const/4 v0, 0x0\n    return v0\n"
	sigs := []string{
		`.method static compareSignatures([Landroid/content/pm/Signature;[Landroid/content/pm/Signature;)I`,
		`.method private compareSignaturesCompat(Lcom/android/server/pm/PackageSignatures;Landroid/content/pm/PackageParser$Package;)I`,
		`.method private compareSignaturesRecover(Lcom/android/server/pm/PackageSignatures;Landroid/content/pm/PackageParser$Package;)I`,
	}
	for _, sig := range sigs {
		start := strings.Index(text, sig)
		if start < 0 {
			return fmt.Errorf("не найден метод: %s", sig)
		}
		rest := text[start:]
		endRel := strings.Index(rest, "\n.end method")
		if endRel < 0 {
			return fmt.Errorf("нет .end method для %s", sig)
		}
		end := start + endRel + len("\n.end method")
		repl := sig + "\n" + stub + ".end method"
		text = text[:start] + repl + text[end:]
	}
	return os.WriteFile(path, []byte(text), 0o644)
}

func injectDexIntoJar(jarPath, dexPath string) error {
	r, err := zip.OpenReader(jarPath)
	if err != nil {
		return err
	}
	entries := map[string][]byte{}
	for _, f := range r.File {
		if f.Name == "classes.dex" {
			continue
		}
		rc, err := f.Open()
		if err != nil {
			r.Close()
			return err
		}
		b, err := io.ReadAll(rc)
		rc.Close()
		if err != nil {
			r.Close()
			return err
		}
		entries[f.Name] = b
	}
	r.Close()

	dex, err := os.ReadFile(dexPath)
	if err != nil {
		return err
	}

	tmp := jarPath + ".tmp"
	w, err := os.Create(tmp)
	if err != nil {
		return err
	}
	zw := zip.NewWriter(w)
	for name, data := range entries {
		fw, err := zw.Create(name)
		if err != nil {
			zw.Close()
			w.Close()
			_ = os.Remove(tmp)
			return err
		}
		if _, err := fw.Write(data); err != nil {
			zw.Close()
			w.Close()
			_ = os.Remove(tmp)
			return err
		}
	}
	fw, err := zw.Create("classes.dex")
	if err != nil {
		zw.Close()
		w.Close()
		_ = os.Remove(tmp)
		return err
	}
	if _, err := fw.Write(dex); err != nil {
		zw.Close()
		w.Close()
		_ = os.Remove(tmp)
		return err
	}
	if err := zw.Close(); err != nil {
		w.Close()
		_ = os.Remove(tmp)
		return err
	}
	if err := w.Close(); err != nil {
		_ = os.Remove(tmp)
		return err
	}
	return os.Rename(tmp, jarPath)
}
