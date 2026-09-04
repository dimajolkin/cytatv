package oemhack

import (
	"encoding/binary"
	"fmt"
	"os"
	"path/filepath"
)

const dtFlags1 = 0x6FFFFFFB

// clearDTFlags1 clears DT_FLAGS_1 in ELF32 LE (old Android Bionic rejects DF_1_PIE|NOW).
func clearDTFlags1(path string) (int, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return 0, err
	}
	if len(data) < 52 || string(data[:4]) != "\x7fELF" || data[4] != 1 || data[5] != 1 {
		return 0, nil // not ELF32 LE
	}
	ePhoff := binary.LittleEndian.Uint32(data[28:32])
	ePhentsize := binary.LittleEndian.Uint16(data[42:44])
	ePhnum := binary.LittleEndian.Uint16(data[44:46])
	fixed := 0
	buf := append([]byte(nil), data...)
	for i := uint16(0); i < ePhnum; i++ {
		off := int(ePhoff) + int(i)*int(ePhentsize)
		if off+32 > len(buf) {
			break
		}
		pType := binary.LittleEndian.Uint32(buf[off:])
		if pType != 2 { // PT_DYNAMIC
			continue
		}
		pOffset := binary.LittleEndian.Uint32(buf[off+4:])
		pFilesz := binary.LittleEndian.Uint32(buf[off+16:])
		for j := uint32(0); j+8 <= pFilesz; j += 8 {
			entry := int(pOffset) + int(j)
			if entry+8 > len(buf) {
				break
			}
			tag := binary.LittleEndian.Uint32(buf[entry:])
			val := binary.LittleEndian.Uint32(buf[entry+4:])
			if tag == 0 {
				break
			}
			if tag == dtFlags1 && val != 0 {
				fmt.Printf("%s: DT_FLAGS_1 %#x -> 0\n", filepath.Base(path), val)
				binary.LittleEndian.PutUint32(buf[entry+4:], 0)
				fixed++
			}
		}
	}
	if fixed > 0 {
		st, _ := os.Stat(path)
		mode := os.FileMode(0o755)
		if st != nil {
			mode = st.Mode().Perm()
		}
		if err := os.WriteFile(path, buf, mode); err != nil {
			return fixed, err
		}
	}
	return fixed, nil
}

func clearDTFlags1Files(paths ...string) {
	total := 0
	for _, p := range paths {
		n, err := clearDTFlags1(p)
		if err != nil {
			fmt.Printf("elf-clear %s: %v\n", p, err)
			continue
		}
		total += n
	}
	fmt.Printf("cleared %d DT_FLAGS_1 entr(y/ies)\n", total)
}
