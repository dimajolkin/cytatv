package oemhack

import "testing"

func TestPropValue(t *testing.T) {
	bp := "ro.foo=1\n# ro.oem_preferred_pkg=old\nro.oem_preferred_pkg=com.benny.openlauncher\n"
	if g := propValue(bp, "ro.oem_preferred_pkg"); g != "com.benny.openlauncher" {
		t.Fatalf("got %q", g)
	}
	if g := propValue(bp, "missing"); g != "" {
		t.Fatalf("want empty, got %q", g)
	}
}

func TestReserveHasPackage(t *testing.T) {
	xml := renderReserveAPP([]string{"system", "com.benny.openlauncher"})
	if !reserveHasPackage(xml, "com.benny.openlauncher") {
		t.Fatal("expected package")
	}
	if reserveHasPackage(xml, "ch.deletescape.lawnchair") {
		t.Fatal("unexpected package")
	}
}
