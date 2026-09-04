package config

import (
	"fmt"
	"os"

	"gopkg.in/yaml.v3"
)

// Ubuntu — configs/ubuntu.yaml.
type Ubuntu struct {
	Version        string `yaml:"version"`
	Codename       string `yaml:"codename"`
	SizeGB         int    `yaml:"size_gb"`
	BaseURL        string `yaml:"base_url"`
	AuthorizedKeys string `yaml:"authorized_keys"`
	Output         string `yaml:"output"`
	Flash          Flash  `yaml:"flash"`
}

func loadUbuntu(path string) (Ubuntu, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return Ubuntu{}, err
	}
	var c Ubuntu
	if err := yaml.Unmarshal(b, &c); err != nil {
		return Ubuntu{}, fmt.Errorf("%s: %w", path, err)
	}
	return c, nil
}

func (c Ubuntu) Validate() error {
	for _, f := range []struct {
		name string
		ok   bool
	}{
		{"ubuntu.version", c.Version != ""},
		{"ubuntu.codename", c.Codename != ""},
		{"ubuntu.size_gb", c.SizeGB > 0},
		{"ubuntu.base_url", c.BaseURL != ""},
		{"ubuntu.authorized_keys", c.AuthorizedKeys != ""},
		{"ubuntu.output", c.Output != ""},
	} {
		if !f.ok {
			return errRequired(f.name)
		}
	}
	return nil
}
