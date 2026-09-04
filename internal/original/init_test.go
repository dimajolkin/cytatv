package original

import (
	"os"
	"path/filepath"
	"testing"

	"cytatv/internal/config"
)

func TestFindDumpImgAndDmg(t *testing.T) {
	dir := t.TempDir()
	o := config.Original{Dir: dir, Image: "original.img"}

	if _, err := FindDump(o); err == nil {
		t.Fatal("expected missing dump")
	}

	dmg := filepath.Join(dir, "original.dmg")
	if err := os.WriteFile(dmg, []byte("fake-dump"), 0o644); err != nil {
		t.Fatal(err)
	}
	got, err := FindDump(o)
	if err != nil {
		t.Fatal(err)
	}
	if got != dmg {
		t.Fatalf("got %s want %s", got, dmg)
	}

	img := filepath.Join(dir, "original.img")
	if err := os.WriteFile(img, []byte("prefer-img"), 0o644); err != nil {
		t.Fatal(err)
	}
	got, err = FindDump(o)
	if err != nil {
		t.Fatal(err)
	}
	if got != img {
		t.Fatalf("prefer img: got %s", got)
	}
}
