package oemhack

import (
	"os"
	"path/filepath"
	"strings"
)

func stageWifiCalFirmware(b *Job) error {
	// filesystems/system → sibling userdata
	fsRoot := filepath.Dir(b.Cfg.FilesystemDir)
	calSrc := filepath.Join(fsRoot, "userdata", "wifi", "cal", "wlan_eeprom.bin")
	calHash := filepath.Join(fsRoot, "userdata", "wifi", "cal", "binsha256")

	if _, err := os.Stat(calSrc); err == nil {
		b.logf("wifi cal → /etc/wifi/cal")
		conf := b.work("wifi_cal.conf")
		if err := b.Dump("/etc/wifi/wifi_cal.conf", conf); err == nil {
			data, err := os.ReadFile(conf)
			if err != nil {
				return err
			}
			var out []string
			replaced := false
			for _, line := range strings.Split(string(data), "\n") {
				if strings.HasPrefix(line, "CUST_EEPROMLoadPath=") {
					out = append(out, "CUST_EEPROMLoadPath=/system/etc/wifi/cal/wlan_eeprom.bin")
					replaced = true
				} else {
					out = append(out, line)
				}
			}
			if !replaced {
				out = append(out, "CUST_EEPROMLoadPath=/system/etc/wifi/cal/wlan_eeprom.bin")
			}
			text := strings.Join(out, "\n")
			if !strings.HasSuffix(text, "\n") {
				text += "\n"
			}
			if err := os.WriteFile(conf, []byte(text), 0o644); err != nil {
				return err
			}
			if err := b.WriteBack(conf, "/etc/wifi/wifi_cal.conf", ""); err != nil {
				return err
			}
		}
		b.Mkdir("/etc/wifi/cal")
		if err := b.WriteBack(calSrc, "/etc/wifi/cal/wlan_eeprom.bin", "0100644"); err != nil {
			return err
		}
		if _, err := os.Stat(calHash); err == nil {
			_ = b.WriteBack(calHash, "/etc/wifi/cal/binsha256", "0100600")
		}
	} else {
		b.logf("WARN: нет %s — WiFi после wipe userdata может не подняться", calSrc)
	}

	for _, fw := range []string{"mt7662t_patch_e1_hdr.bin", "mt7662t_firmware_e1.bin"} {
		src := "/etc/firmware/" + fw
		dst := "/lib/firmware/" + fw
		if !b.Stat(src) {
			continue
		}
		tmp := b.work("fw-" + fw)
		if err := b.Dump(src, tmp); err != nil {
			continue
		}
		b.Rm(dst)
		if err := b.WriteBack(tmp, dst, "0100644"); err != nil {
			return err
		}
		b.logf("  %s → lib/firmware", fw)
	}
	return nil
}
