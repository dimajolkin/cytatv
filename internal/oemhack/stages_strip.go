package oemhack

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

var keepApp = map[string]bool{
	"BLERemoteControl": true, "Bluetooth": true, "Browser2": true,
	"CertInstaller": true, "DownloadProviderUi": true, "ExtShared": true,
	"Gallery2": true, "HTMLViewer": true, "HiRMService": true,
	"HmtBluetooth": true, "HmtCombinedKeyService": true, "HmtNetworkService": true,
	"HmtStatusToast": true, "HmtStbAPIService": true, "HmtStbBgService": true,
	"HmtStbConfigProvider": true, "KeyChain": true, "LatinIME": true,
	"PacProcessor": true, "PrintSpooler": true, "Settings": true,
	"UserDictionaryProvider": true, "WallpaperBackup": true, "webview": true,
}

func stageStripOperator(b *Build) error {
	fsRoot := b.Cfg.FilesystemDir
	if _, err := os.Stat(fsRoot); err != nil {
		return fmt.Errorf("нет filesystem dump %s", fsRoot)
	}

	var trees []string
	appDir := filepath.Join(fsRoot, "app")
	entries, err := os.ReadDir(appDir)
	if err != nil {
		return err
	}
	for _, e := range entries {
		if keepApp[e.Name()] {
			continue
		}
		trees = append(trees, "app/"+e.Name())
	}
	trees = append(trees, "iptv", "bin/iptv-setup")

	libDir := filepath.Join(fsRoot, "lib")
	if libs, err := os.ReadDir(libDir); err == nil {
		for _, e := range libs {
			low := strings.ToLower(e.Name())
			if strings.Contains(low, "iptv") || strings.Contains(low, "vriptv") {
				trees = append(trees, "lib/"+e.Name())
			}
		}
	}
	if _, err := os.Stat(filepath.Join(fsRoot, "media", "bootanimation.zip")); err == nil {
		trees = append(trees, "media/bootanimation.zip")
	}

	var files, dirs []string
	for _, tree := range trees {
		base := filepath.Join(fsRoot, filepath.FromSlash(tree))
		st, err := os.Stat(base)
		if err != nil {
			b.logf("skip %s", tree)
			continue
		}
		if !st.IsDir() {
			files = append(files, tree)
			continue
		}
		_ = filepath.Walk(base, func(path string, info os.FileInfo, err error) error {
			if err != nil {
				return nil
			}
			if info.IsDir() {
				return nil
			}
			rel, _ := filepath.Rel(fsRoot, path)
			files = append(files, filepath.ToSlash(rel))
			return nil
		})
		var localDirs []string
		_ = filepath.WalkDir(base, func(path string, d os.DirEntry, err error) error {
			if err != nil || !d.IsDir() {
				return nil
			}
			rel, _ := filepath.Rel(fsRoot, path)
			rel = filepath.ToSlash(rel)
			if rel != "." {
				localDirs = append(localDirs, rel)
			}
			return nil
		})
		for i := len(localDirs) - 1; i >= 0; i-- {
			dirs = append(dirs, localDirs[i])
		}
	}

	seen := map[string]bool{}
	var cmds []string
	for _, p := range files {
		if seen[p] {
			continue
		}
		seen[p] = true
		cmds = append(cmds, "rm /"+p)
	}
	for _, p := range dirs {
		if seen[p] {
			continue
		}
		seen[p] = true
		cmds = append(cmds, "rmdir /"+p)
	}

	b.logf("remove: %d trees → %d files, %d dirs", len(trees), len(files), len(dirs))
	if len(cmds) == 0 {
		return nil
	}
	return b.debugfsFile(strings.Join(cmds, "\n") + "\n")
}
