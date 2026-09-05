package flash

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
)

// Sudo запускает команду через sudo с пробросом stdio (как ubuntu dd).
func Sudo(name string, args ...string) error {
	cmd := exec.Command("sudo", append([]string{name}, args...)...)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("sudo %s: %w", name, err)
	}
	return nil
}

// Elevate перезапускает текущий процесс через sudo, если нет root.
// extra — доп. флаги для дочернего процесса (например -d disk12 --force).
// strip — флаги, которые нужно убрать (например --build после подготовки в parent).
// При успехе parent завершается с кодом 0.
func Elevate(extra, strip []string) error {
	if os.Geteuid() == 0 {
		return nil
	}
	fmt.Fprintln(os.Stderr, "нужен root — sudo…")
	args := stripFlags(os.Args, strip)
	args = append(args, extra...)
	cmd := exec.Command("sudo", args...)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		return err
	}
	os.Exit(0)
	return nil
}

func stripFlags(args, strip []string) []string {
	if len(strip) == 0 {
		return append([]string{}, args...)
	}
	skip := map[string]bool{}
	for _, s := range strip {
		skip[s] = true
	}
	out := make([]string, 0, len(args))
	for i := 0; i < len(args); i++ {
		a := args[i]
		if skip[a] {
			continue
		}
		// --flag=value
		if eq := strings.IndexByte(a, '='); eq > 0 && skip[a[:eq]] {
			continue
		}
		out = append(out, a)
	}
	return out
}
