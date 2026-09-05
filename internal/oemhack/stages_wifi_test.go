package oemhack

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"cytatv/internal/config"
)

func TestEscapeConfValue(t *testing.T) {
	got := escapeConfValue("a\\b\nc")
	if got != `a\\b\nc` {
		t.Fatalf("%q", got)
	}
}

func TestWifiDefaultConfBody(t *testing.T) {
	w := config.Wifi{SSID: "Kracozabra", PSK: "secret"}
	keyMgmt := "WPA-PSK"
	body := "ssid=" + escapeConfValue(w.SSID) + "\n" +
		"psk=" + escapeConfValue(w.PSK) + "\n" +
		"key_mgmt=" + escapeConfValue(keyMgmt) + "\n"
	if !strings.Contains(body, "ssid=Kracozabra\n") {
		t.Fatal(body)
	}
	dir := t.TempDir()
	p := filepath.Join(dir, "cytatv_default.conf")
	if err := os.WriteFile(p, []byte(body), 0o600); err != nil {
		t.Fatal(err)
	}
}
