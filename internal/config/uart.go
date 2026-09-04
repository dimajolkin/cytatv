package config

import (
	"fmt"
	"os"

	"gopkg.in/yaml.v3"
)

// Uart — configs/uart.yaml.
type Uart struct {
	Port   string `yaml:"port"`
	Baud   int    `yaml:"baud"`
	LogDir string `yaml:"log_dir"`
}

func loadUart(path string) (Uart, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return Uart{}, err
	}
	var c Uart
	if err := yaml.Unmarshal(b, &c); err != nil {
		return Uart{}, fmt.Errorf("%s: %w", path, err)
	}
	return c, nil
}

func (c Uart) Validate() error {
	if c.Baud <= 0 {
		return errRequired("uart.baud")
	}
	if c.LogDir == "" {
		return errRequired("uart.log_dir")
	}
	return nil
}
