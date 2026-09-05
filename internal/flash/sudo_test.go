package flash

import (
	"reflect"
	"testing"
)

func TestStripFlags(t *testing.T) {
	in := []string{"q22e", "aoh", "flash", "--build", "-d", "disk12", "--verify"}
	got := stripFlags(in, []string{"--build"})
	want := []string{"q22e", "aoh", "flash", "-d", "disk12", "--verify"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %v want %v", got, want)
	}
	got = stripFlags(in, []string{"--build", "--verify"})
	want = []string{"q22e", "aoh", "flash", "-d", "disk12"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %v want %v", got, want)
	}
}
