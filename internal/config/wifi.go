package config

// Wifi — дефолтная STA-сеть после прошивки (обычно в .local.yaml).
// Пустой ssid = не сидить.
type Wifi struct {
	SSID    string `yaml:"ssid"`
	PSK     string `yaml:"psk"`
	KeyMgmt string `yaml:"key_mgmt"` // WPA-PSK (default) | NONE
}
