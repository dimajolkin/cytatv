package logo

import (
	"encoding/binary"
	"fmt"
	"os"
	"path/filepath"
)

// Config — HiSi splash из JPEG (часть android-oem-hack).
type Config struct {
	Enabled bool   `yaml:"enabled"`
	JPEG    string `yaml:"jpeg"`
	SizeMiB int    `yaml:"size_mib"`
	OutFile string // absolute, set by caller (assets/logo/logo-neutral.img)
}

// Validate checks fields when Enabled.
func (c Config) Validate() error {
	if !c.Enabled {
		return nil
	}
	if c.JPEG == "" {
		return fmt.Errorf("logo.jpeg обязателен при logo.enabled")
	}
	if c.SizeMiB <= 0 {
		return fmt.Errorf("logo.size_mib обязателен при logo.enabled")
	}
	if c.OutFile == "" {
		return fmt.Errorf("logo out_file обязателен при logo.enabled")
	}
	return nil
}

// Build converts JPEG → HiSi logo.img and pads to SizeMiB.
func Build(cfg Config) error {
	if err := cfg.Validate(); err != nil {
		return err
	}
	if !cfg.Enabled {
		return nil
	}

	jpg, err := os.ReadFile(cfg.JPEG)
	if err != nil {
		return fmt.Errorf("logo.jpeg: %w", err)
	}
	w, h, err := jpegSize(jpg)
	if err != nil {
		return err
	}
	if !((w == 1920 && h == 1080) || (w == 1280 && h == 720)) {
		return fmt.Errorf("logo: %dx%d не поддерживается HiSi (нужен 1920x1080 или 1280x720)", w, h)
	}

	raw := encodeHisi(jpg)
	pad := cfg.SizeMiB * 1024 * 1024
	if len(raw) > pad {
		return fmt.Errorf("logo: образ %d больше partition %d MiB", len(raw), cfg.SizeMiB)
	}
	out := make([]byte, pad)
	copy(out, raw)

	if err := os.MkdirAll(filepath.Dir(cfg.OutFile), 0o755); err != nil {
		return err
	}
	if err := os.WriteFile(cfg.OutFile, out, 0o644); err != nil {
		return err
	}
	fmt.Printf("=== logo (HiSi %dx%d) ===\n  %s %d\n", w, h, cfg.OutFile, len(out))
	return nil
}

func encodeHisi(jpg []byte) []byte {
	// Port of scripts/hisi-logo/jpeg2hisi.py (HisiLogoTool).
	buf := make([]byte, 0, 0x2000+len(jpg))
	buf = append(buf, '#', '#', '#')
	buf = append(buf, 0x00, 0x7c, 0x00, 0x00, 0x00)
	buf = append(buf, []byte("LOGO_TABLE")...)
	buf = append(buf, make([]byte, 22)...)
	buf = append(buf, 0x50)
	buf = append(buf, 0x00, 0x00, 0x00)
	buf = append(buf, []byte("LOGO_KEY_FLAG")...)
	buf = append(buf, make([]byte, 19)...)
	buf = append(buf, 0x04)
	buf = append(buf, 0x00, 0x00, 0x00)
	buf = append(buf, 0x01)
	buf = append(buf, 0x00, 0x00, 0x00)
	buf = append(buf, []byte("LOGO_KEY_LEN")...)
	buf = append(buf, make([]byte, 20)...)
	buf = append(buf, 0x04)
	buf = append(buf, 0x00, 0x00, 0x00)
	var sizeLE [8]byte
	binary.LittleEndian.PutUint64(sizeLE[:], uint64(len(jpg)))
	buf = append(buf, sizeLE[:]...)
	if len(buf) > 0x2000 {
		panic("hisi logo header overflow")
	}
	pad := make([]byte, 0x2000-len(buf))
	buf = append(buf, pad...)
	buf = append(buf, jpg...)
	return buf
}

func jpegSize(data []byte) (w, h int, err error) {
	if len(data) < 4 || data[0] != 0xff || data[1] != 0xd8 {
		return 0, 0, fmt.Errorf("logo: не JPEG")
	}
	pos := 2
	for pos+9 < len(data) {
		if data[pos] != 0xff {
			return 0, 0, fmt.Errorf("logo: битый JPEG (marker)")
		}
		for data[pos] == 0xff {
			pos++
			if pos >= len(data) {
				return 0, 0, fmt.Errorf("logo: битый JPEG")
			}
		}
		ftype := data[pos]
		pos++
		if pos+1 >= len(data) {
			return 0, 0, fmt.Errorf("logo: битый JPEG (size)")
		}
		segLen := int(binary.BigEndian.Uint16(data[pos : pos+2]))
		if segLen < 2 || pos+segLen > len(data) {
			return 0, 0, fmt.Errorf("logo: битый JPEG (segment)")
		}
		if ftype >= 0xc0 && ftype <= 0xcf && ftype != 0xc4 && ftype != 0xc8 && ftype != 0xcc {
			// SOF: precision, height, width
			h = int(binary.BigEndian.Uint16(data[pos+3 : pos+5]))
			w = int(binary.BigEndian.Uint16(data[pos+5 : pos+7]))
			return w, h, nil
		}
		pos += segLen
	}
	return 0, 0, fmt.Errorf("logo: нет SOF в JPEG")
}
