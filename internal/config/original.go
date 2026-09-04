package config

import (
	"fmt"
	"os"
	"path/filepath"

	"gopkg.in/yaml.v3"
)

// Original — configs/original.yaml (ISP-дамп → partitions/filesystems).
type Original struct {
	Dir         string   `yaml:"dir"`
	Image       string   `yaml:"image"` // имя файла в dir, обычно original.img
	XML         string   `yaml:"xml"`
	Filesystems []string `yaml:"filesystems"`
}

func loadOriginal(path string) (Original, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return Original{}, err
	}
	var c Original
	if err := yaml.Unmarshal(b, &c); err != nil {
		return Original{}, fmt.Errorf("%s: %w", path, err)
	}
	return c, nil
}

func (c Original) Validate() error {
	if c.Dir == "" {
		return errRequired("original.dir")
	}
	if c.Image == "" {
		return errRequired("original.image")
	}
	if c.XML == "" {
		return errRequired("original.xml")
	}
	if len(c.Filesystems) == 0 {
		return errRequired("original.filesystems[]")
	}
	return nil
}

// ImagePath — абсолютный путь к full dump.
func (c Original) ImagePath() string {
	if filepath.IsAbs(c.Image) {
		return c.Image
	}
	return filepath.Join(c.Dir, c.Image)
}

// PartitionsDir — dir/partitions.
func (c Original) PartitionsDir() string {
	return filepath.Join(c.Dir, "partitions")
}

// FilesystemsDir — dir/filesystems.
func (c Original) FilesystemsDir() string {
	return filepath.Join(c.Dir, "filesystems")
}
