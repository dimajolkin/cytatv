package builder

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"cytatv/internal/config"
)

// Ubuntu downloads Base, builds Docker image, runs mkimage.
func Ubuntu(cfg config.Config) error {
	u := cfg.Ubuntu
	outDir := filepath.Dir(u.Output)
	dlDir := filepath.Join(outDir, "dl")
	workDir := filepath.Join(outDir, "work")
	for _, d := range []string{dlDir, outDir, workDir} {
		if err := os.MkdirAll(d, 0o755); err != nil {
			return err
		}
	}

	baseName := fmt.Sprintf("ubuntu-base-%s-base-armhf.tar.gz", u.Version)
	archive := filepath.Join(dlDir, baseName)
	if !fileExists(archive) {
		url := strings.TrimRight(u.BaseURL, "/") + "/" + baseName
		fmt.Println("=== download", baseName, "===")
		if err := run(cfg.Root, "curl", "-fL", "--retry", "3", "-o", archive, url); err != nil {
			return err
		}
	}
	if err := verifySHA256(dlDir, baseName, archive, u.BaseURL); err != nil {
		return err
	}
	fmt.Println("SHA256 OK")

	fmt.Println("=== docker build q22e-ubuntu-builder ===")
	ctx := filepath.Join(cfg.Root, "internal", "ubuntu")
	if err := run(cfg.Root, "docker", "build", "-t", "q22e-ubuntu-builder", ctx); err != nil {
		return err
	}

	noKeys := "1"
	args := []string{
		"run", "--rm", "--privileged",
		"-e", fmt.Sprintf("SIZE_GB=%d", u.SizeGB),
		"-e", "UBUNTU_CODENAME=" + u.Codename,
		"-v", archive + ":/in/base.tar.gz:ro",
		"-v", workDir + ":/work",
		"-v", outDir + ":/out",
	}
	if fileExists(u.AuthorizedKeys) {
		noKeys = "0"
		args = append(args, "-v", u.AuthorizedKeys+":/keys/authorized_keys:ro")
	}
	args = append(args, "-e", "NO_KEYS="+noKeys, "q22e-ubuntu-builder")

	fmt.Println("=== docker run mkimage ===")
	if err := run(cfg.Root, "docker", args...); err != nil {
		return err
	}

	manifest := filepath.Join(outDir, "MANIFEST.txt")
	_ = os.WriteFile(manifest, []byte(fmt.Sprintf(
		"ubuntu-chroot (Ubuntu Base %s armhf)\nbuilt by: q22e ubuntu build\nimage: %s\nsize_gb: %d\n",
		u.Version, u.Output, u.SizeGB,
	)), 0o644)

	fmt.Println("OK:", u.Output)
	return nil
}

func verifySHA256(dlDir, baseName, archive, baseURL string) error {
	sums := filepath.Join(dlDir, "SHA256SUMS")
	if !fileExists(sums) {
		url := strings.TrimRight(baseURL, "/") + "/SHA256SUMS"
		_ = run(dlDir, "curl", "-fL", "--retry", "2", "-o", sums, url)
	}
	if !fileExists(sums) {
		fmt.Println("WARN: no SHA256SUMS, skip verify")
		return nil
	}
	b, err := os.ReadFile(sums)
	if err != nil {
		return err
	}
	var expect string
	for _, line := range strings.Split(string(b), "\n") {
		fields := strings.Fields(line)
		if len(fields) < 2 {
			continue
		}
		name := strings.TrimPrefix(fields[1], "*")
		if name == baseName {
			expect = fields[0]
			break
		}
	}
	if expect == "" {
		return fmt.Errorf("SHA256SUMS: no entry for %s", baseName)
	}
	out, err := exec.Command("shasum", "-a", "256", archive).Output()
	if err != nil {
		return err
	}
	got := strings.Fields(string(out))[0]
	if got != expect {
		return fmt.Errorf("SHA256 mismatch expect=%s got=%s", expect, got)
	}
	return nil
}

func run(dir, name string, args ...string) error {
	cmd := exec.Command(name, args...)
	cmd.Dir = dir
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}
