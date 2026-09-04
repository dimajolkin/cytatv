package original

import (
	"encoding/xml"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
)

const MiB = 1024 * 1024

// Part — слот из emmc_partitions XML.
type Part struct {
	Name   string
	Start  uint64
	Length uint64 // 0 = до EOF
	FS     string // ext4 | none | …
}

type partitionXML struct {
	Parts []partXML `xml:"Part"`
}

type partXML struct {
	Name   string `xml:"PartitionName,attr"`
	Start  string `xml:"Start,attr"`
	Length string `xml:"Length,attr"`
	FS     string `xml:"FileSystem,attr"`
}

var sizeRE = regexp.MustCompile(`(?i)^(\d+)(M|K|G)?$`)

// LoadParts читает configs/emmc_partitions_*.xml.
func LoadParts(xmlPath string) ([]Part, error) {
	b, err := os.ReadFile(xmlPath)
	if err != nil {
		return nil, err
	}
	var doc partitionXML
	if err := xml.Unmarshal(b, &doc); err != nil {
		return nil, fmt.Errorf("%s: %w", xmlPath, err)
	}
	out := make([]Part, 0, len(doc.Parts))
	for _, p := range doc.Parts {
		start, err := parseSize(p.Start)
		if err != nil {
			return nil, fmt.Errorf("%s start %q: %w", p.Name, p.Start, err)
		}
		length, err := parseSize(p.Length)
		if err != nil {
			return nil, fmt.Errorf("%s length %q: %w", p.Name, p.Length, err)
		}
		// userdata в XML часто урезан — режем до EOF
		if strings.EqualFold(p.Name, "userdata") {
			length = 0
		}
		out = append(out, Part{
			Name:   p.Name,
			Start:  start,
			Length: length,
			FS:     strings.ToLower(p.FS),
		})
	}
	return out, nil
}

func parseSize(s string) (uint64, error) {
	s = strings.TrimSpace(s)
	m := sizeRE.FindStringSubmatch(s)
	if m == nil {
		return 0, fmt.Errorf("ожидался N/NM/NK/NG")
	}
	n, err := strconv.ParseUint(m[1], 10, 64)
	if err != nil {
		return 0, err
	}
	switch strings.ToUpper(m[2]) {
	case "", "M":
		return n * MiB, nil
	case "K":
		return n * 1024, nil
	case "G":
		return n * MiB * 1024, nil
	default:
		return 0, fmt.Errorf("единица %q", m[2])
	}
}

// SlicePartitions пишет part.img из full image.
func SlicePartitions(image string, parts []Part, outDir string, force bool) error {
	fi, err := os.Stat(image)
	if err != nil {
		return err
	}
	imgSize := uint64(fi.Size())
	if err := os.MkdirAll(outDir, 0o755); err != nil {
		return err
	}
	src, err := os.Open(image)
	if err != nil {
		return err
	}
	defer src.Close()

	for _, p := range parts {
		if p.Start >= imgSize {
			fmt.Printf("  skip %s (start за EOF)\n", p.Name)
			continue
		}
		length := p.Length
		if length == 0 || p.Start+length > imgSize {
			length = imgSize - p.Start
		}
		dest := filepath.Join(outDir, p.Name+".img")
		if !force {
			if st, err := os.Stat(dest); err == nil && uint64(st.Size()) == length {
				fmt.Printf("  OK  %s (%d MiB)\n", p.Name+".img", length/MiB)
				continue
			}
		}
		fmt.Printf("  →  %s @ %d MiB, %d MiB\n", p.Name, p.Start/MiB, length/MiB)
		if err := copyRange(src, dest, int64(p.Start), int64(length)); err != nil {
			return fmt.Errorf("%s: %w", p.Name, err)
		}
	}
	return nil
}

func copyRange(src *os.File, dest string, offset, length int64) error {
	if _, err := src.Seek(offset, io.SeekStart); err != nil {
		return err
	}
	tmp := dest + ".partial"
	f, err := os.Create(tmp)
	if err != nil {
		return err
	}
	n, err := io.Copy(f, io.LimitReader(src, length))
	cerr := f.Close()
	if err != nil {
		_ = os.Remove(tmp)
		return err
	}
	if cerr != nil {
		_ = os.Remove(tmp)
		return cerr
	}
	if n != length {
		_ = os.Remove(tmp)
		return fmt.Errorf("скопировано %d из %d", n, length)
	}
	return os.Rename(tmp, dest)
}
