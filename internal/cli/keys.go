package cli

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"

	"cytatv/internal/config"
)

const sshKeyName = "id_ed25519_q22e"

// GenerateSSHKeys пишет ed25519 в assets/ssh/ (+ authorized_keys).
func GenerateSSHKeys(cfg config.Config, force bool) error {
	dir := filepath.Join(cfg.Root, "assets", "ssh")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	priv := filepath.Join(dir, sshKeyName)
	pub := priv + ".pub"
	auth := filepath.Join(dir, "authorized_keys")

	if !force {
		for _, p := range []string{priv, pub, auth} {
			if _, err := os.Stat(p); err == nil {
				return fmt.Errorf("%s уже есть — перезапись: q22e keys --force", p)
			}
		}
	} else {
		_ = os.Remove(priv)
		_ = os.Remove(pub)
		_ = os.Remove(auth)
	}

	cmd := exec.Command("ssh-keygen",
		"-t", "ed25519",
		"-f", priv,
		"-N", "",
		"-C", "q22e",
	)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("ssh-keygen: %w", err)
	}

	pubBytes, err := os.ReadFile(pub)
	if err != nil {
		return err
	}
	if err := os.WriteFile(auth, pubBytes, 0o644); err != nil {
		return err
	}
	_ = os.Chmod(priv, 0o600)
	_ = os.Chmod(auth, 0o644)

	fmt.Println("=== SSH keys ===")
	fmt.Println("  private:", priv)
	fmt.Println("  public: ", pub)
	fmt.Println("  auth:   ", auth)
	fmt.Println("Подключение: ssh -i", priv, "root@<IP>")
	return nil
}
