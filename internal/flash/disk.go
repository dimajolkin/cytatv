package flash

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"strconv"
	"strings"
)

var (
	diskNameRE   = regexp.MustCompile(`^disk[0-9]+$`)
	diskListRE   = regexp.MustCompile(`(?m)^/dev/(disk\d+)\s+\(([^)]+)\):`)
	diskSizeRE   = regexp.MustCompile(`\((\d+)\s+Bytes\)`)
)

// Candidate — диск, пригодный для flash.
type Candidate struct {
	ID       string // disk11
	Name     string // Built In SDXC Reader
	Protocol string // Secure Digital
	Size     uint64
	Internal bool
}

// Label — строка для списка: disk11 — Built In SDXC Reader (29.7 GB).
func (c Candidate) Label() string {
	name := c.Name
	if name == "" {
		name = "—"
	}
	tag := ""
	if looksLikeEMMC(c) {
		tag = " ★ eMMC"
	}
	extra := ""
	if c.Protocol != "" {
		extra = "  [" + c.Protocol + "]"
	}
	return fmt.Sprintf("%s — %s (%s)%s%s", c.ID, name, humanBytes(c.Size), tag, extra)
}

func looksLikeEMMC(c Candidate) bool {
	n := strings.ToLower(c.Name)
	if strings.Contains(n, "socket") || strings.Contains(n, "emmc") {
		return true
	}
	const approx = 7818182656
	return c.Size > approx-64<<20 && c.Size < approx+64<<20
}

// ValidateName проверяет формат diskN и запрещает disk0.
func ValidateName(disk string) error {
	if !diskNameRE.MatchString(disk) {
		return fmt.Errorf("неверный формат: %q (ожидается diskN)", disk)
	}
	if disk == "disk0" {
		return fmt.Errorf("отказ: disk0 — системный диск")
	}
	return nil
}

// RawPath — /dev/rdiskN.
func RawPath(disk string) string { return "/dev/r" + disk }

// DevPath — /dev/diskN.
func DevPath(disk string) string { return "/dev/" + disk }

// Info — media name и protocol из diskutil.
func Info(disk string) (media, proto string, err error) {
	out, err := exec.Command("diskutil", "info", DevPath(disk)).CombinedOutput()
	if err != nil {
		return "", "", fmt.Errorf("diskutil info %s: %w", DevPath(disk), err)
	}
	info := string(out)
	return awkField(info, "Device / Media Name"), awkField(info, "Protocol"), nil
}

// ListCandidates — физические диски без системных (SSD/Fabric) и без disk image/synthesized.
// Встроенный SD-ридер допускается.
func ListCandidates() ([]Candidate, error) {
	out, err := exec.Command("diskutil", "list").Output()
	if err != nil {
		return nil, fmt.Errorf("diskutil list: %w", err)
	}
	matches := diskListRE.FindAllStringSubmatch(string(out), -1)
	var list []Candidate
	for _, m := range matches {
		id, meta := m[1], m[2]
		if !strings.Contains(meta, "physical") {
			continue // synthesized / disk image
		}
		if id == "disk0" {
			continue
		}
		info, err := exec.Command("diskutil", "info", DevPath(id)).CombinedOutput()
		if err != nil {
			continue
		}
		text := string(info)
		if reason := unsafeReason(text); reason != "" {
			continue
		}
		c := Candidate{
			ID:       id,
			Name:     awkField(text, "Device / Media Name"),
			Protocol: awkField(text, "Protocol"),
			Internal: strings.Contains(meta, "internal"),
		}
		if c.Name == "" {
			c.Name = awkField(text, "Media Name")
		}
		if sz := awkField(text, "Disk Size"); sz != "" {
			c.Size = parseDiskutilSize(sz)
		}
		list = append(list, c)
	}
	return list, nil
}

// PrintCandidates печатает отфильтрованный список с именами.
func PrintCandidates() error {
	fmt.Println("Доступные диски:")
	list, err := ListCandidates()
	if err != nil {
		return err
	}
	if len(list) == 0 {
		fmt.Println("  (нет подходящих — только системные / disk image)")
		return nil
	}
	for _, c := range list {
		fmt.Printf("  %s\n", c.Label())
	}
	return nil
}

// AssertSafe отказывает системным дискам Mac.
func AssertSafe(disk string) error {
	if err := ValidateName(disk); err != nil {
		return err
	}
	out, err := exec.Command("diskutil", "info", DevPath(disk)).CombinedOutput()
	info := string(out)
	if err != nil {
		return fmt.Errorf("diskutil info %s: %w", DevPath(disk), err)
	}
	if reason := unsafeReason(info); reason != "" {
		return fmt.Errorf("%s:\n%s", reason, summarizeDiskInfo(info))
	}
	return nil
}

// unsafeReason — пусто если диск можно прошивать.
func unsafeReason(info string) string {
	lower := strings.ToLower(info)
	if strings.Contains(lower, "protocol:") && strings.Contains(lower, "apple fabric") {
		return "отказ: системный диск Mac (Apple Fabric)"
	}
	if strings.Contains(lower, "media name:") && strings.Contains(lower, "apple ssd") {
		return "отказ: системный диск Mac (APPLE SSD)"
	}
	// Virtual / disk image по типу носителя
	if strings.Contains(lower, "virtual or physical:") && strings.Contains(lower, "virtual") {
		return "отказ: виртуальный диск"
	}
	internal := strings.Contains(lower, "device location:") && strings.Contains(lower, "internal")
	if internal {
		media := strings.ToLower(awkField(info, "Device / Media Name") + " " + awkField(info, "Protocol"))
		ok := strings.Contains(media, "secure digital") ||
			strings.Contains(media, "sdxc") ||
			strings.Contains(media, "sd card") ||
			strings.Contains(media, "card reader")
		if !ok {
			return "отказ: внутренний диск (не SD-ридер)"
		}
	}
	return ""
}

// PromptDisk спрашивает diskN у пользователя.
func PromptDisk() (string, error) {
	fmt.Print("Введите diskN (например disk4, БЕЗ r): ")
	line, err := bufio.NewReader(os.Stdin).ReadString('\n')
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(line), nil
}

// ConfirmYes требует ввод "yes", если force=false.
func ConfirmYes(prompt string, force bool) error {
	if force {
		return nil
	}
	fmt.Print(prompt)
	line, err := bufio.NewReader(os.Stdin).ReadString('\n')
	if err != nil {
		return err
	}
	if strings.TrimSpace(line) != "yes" {
		return fmt.Errorf("отменено")
	}
	return nil
}

// ResolveDisk — disk из конфига/флага или prompt; validate + AssertSafe.
func ResolveDisk(disk string, force bool) (string, error) {
	if disk == "" {
		var err error
		disk, err = PromptDisk()
		if err != nil {
			return "", err
		}
	} else if err := ConfirmYes(fmt.Sprintf("Подтвердите запись на %s (yes): ", disk), force); err != nil {
		return "", err
	}
	if err := AssertSafe(disk); err != nil {
		return "", err
	}
	return disk, nil
}

// UnmountDisk — diskutil unmountDisk (ошибка игнорируется).
func UnmountDisk(disk string) {
	_ = exec.Command("diskutil", "unmountDisk", DevPath(disk)).Run()
}

// Eject — diskutil eject (ошибка игнорируется).
func Eject(disk string) {
	_ = exec.Command("diskutil", "eject", DevPath(disk)).Run()
}

func awkField(info, key string) string {
	for _, line := range strings.Split(info, "\n") {
		if !strings.Contains(line, key) {
			continue
		}
		parts := strings.SplitN(line, ":", 2)
		if len(parts) == 2 {
			return strings.TrimSpace(parts[1])
		}
	}
	return ""
}

func summarizeDiskInfo(info string) string {
	var lines []string
	for _, key := range []string{"Device Node", "Device / Media Name", "Protocol", "Device Location"} {
		if v := awkField(info, key); v != "" {
			lines = append(lines, "  "+key+": "+v)
		}
	}
	return strings.Join(lines, "\n")
}

func parseDiskutilSize(s string) uint64 {
	if m := diskSizeRE.FindStringSubmatch(s); len(m) == 2 {
		n, _ := strconv.ParseUint(m[1], 10, 64)
		return n
	}
	return 0
}

func humanBytes(n uint64) string {
	const (
		kb = 1024
		mb = kb * 1024
		gb = mb * 1024
	)
	switch {
	case n >= gb:
		return fmt.Sprintf("%.2f GB", float64(n)/float64(gb))
	case n >= mb:
		return fmt.Sprintf("%.1f MB", float64(n)/float64(mb))
	case n == 0:
		return "?"
	default:
		return fmt.Sprintf("%d B", n)
	}
}
