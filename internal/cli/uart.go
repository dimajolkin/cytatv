package cli

import (
	"context"
	"fmt"
	"io"
	"os"
	"os/signal"
	"path/filepath"
	"regexp"
	"syscall"
	"time"

	"go.bug.st/serial"

	"cytatv/internal/config"
)

var uartPortRE = regexp.MustCompile(`(?i)usb|serial|SLAB|wch|ch34|cp21|ftdi`)

// UartCapture читает порт, пишет в stdout + log_dir/boot-log-*.txt. Ctrl+C — чистый выход.
// portOverride — аргумент CLI (пусто → cfg.Uart.Port или автопоиск).
func UartCapture(cfg config.Config, portOverride string) error {
	u := cfg.Uart
	baud := u.Baud
	port := portOverride
	if port == "" {
		port = u.Port
	}
	if port == "" {
		var err error
		port, err = findUartPort()
		if err != nil {
			return err
		}
	}
	if _, err := os.Stat(port); err != nil {
		return fmt.Errorf("порт %s: %w", port, err)
	}

	logDir := u.LogDir
	if err := os.MkdirAll(logDir, 0o755); err != nil {
		return err
	}
	stamp := time.Now().Format("20060102-150405")
	logFile := filepath.Join(logDir, "boot-log-"+stamp+".txt")
	defaultLog := filepath.Join(logDir, "boot-log.txt")

	mode := &serial.Mode{BaudRate: baud}
	p, err := serial.Open(port, mode)
	if err != nil {
		return fmt.Errorf("open %s: %w", port, err)
	}
	defer p.Close()

	f, err := os.Create(logFile)
	if err != nil {
		return err
	}
	defer f.Close()

	fmt.Printf("Порт: %d @ %s\n", baud, port)
	fmt.Printf("Лог:  %s (+ symlink %s)\n", logFile, defaultLog)
	fmt.Println()
	fmt.Println("Подключение: adapter RX→board TX, adapter TX→board RX, GND→GND")
	fmt.Println("Включите или перезагрузите приставку. Ctrl+C — стоп и сохранить лог.")
	fmt.Println()

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	w := io.MultiWriter(os.Stdout, f)
	buf := make([]byte, 4096)
	errCh := make(chan error, 1)
	go func() {
		for {
			n, err := p.Read(buf)
			if n > 0 {
				if _, werr := w.Write(buf[:n]); werr != nil {
					errCh <- werr
					return
				}
			}
			if err != nil {
				if err == io.EOF {
					errCh <- nil
					return
				}
				errCh <- err
				return
			}
		}
	}()

	select {
	case <-ctx.Done():
		fmt.Fprintln(os.Stderr, "\nостановлено")
		_ = p.Close()
		select {
		case <-errCh:
		case <-time.After(300 * time.Millisecond):
		}
	case err := <-errCh:
		if err != nil {
			finishUartLog(f, logFile, defaultLog)
			return err
		}
	}

	finishUartLog(f, logFile, defaultLog)
	fmt.Printf("Сохранено: %s\n", logFile)
	return nil
}

func finishUartLog(f *os.File, logFile, defaultLog string) {
	_ = f.Sync()
	_ = os.Remove(defaultLog)
	if err := os.Symlink(filepath.Base(logFile), defaultLog); err != nil {
		_ = copyFileSimple(logFile, defaultLog)
	}
}

func findUartPort() (string, error) {
	matches, _ := filepath.Glob("/dev/cu.*")
	for _, p := range matches {
		base := filepath.Base(p)
		if uartPortRE.MatchString(base) {
			return p, nil
		}
	}
	fmt.Fprintln(os.Stderr, "USB-UART не найден. Доступные порты:")
	for _, p := range matches {
		fmt.Fprintln(os.Stderr, " ", p)
	}
	return "", fmt.Errorf("укажите порт: q22e uart /dev/cu.…")
}

func copyFileSimple(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.Create(dst)
	if err != nil {
		return err
	}
	defer out.Close()
	_, err = io.Copy(out, in)
	return err
}
