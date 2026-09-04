package config

// Flash — параметры записи на диск (секция flash в yaml).
type Flash struct {
	Disk         string `yaml:"disk"`
	Force        bool   `yaml:"force"`
	Verify       bool   `yaml:"verify"`
	Build        bool   `yaml:"build"`
	WipeUserdata bool   `yaml:"wipe_userdata"`
}
