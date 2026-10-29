//go:build linux

package main

import (
	"fmt"
	"os"
	"syscall"
)

// statMtimeNs returns st's mtime in nanoseconds. Linux's syscall.Stat_t exposes
// this as the Mtim field (darwin uses Mtimespec instead — see stat_darwin.go).
func statMtimeNs(st *syscall.Stat_t) int64 {
	return st.Mtim.Sec*1e9 + st.Mtim.Nsec
}

func diskSegment() {
	var stat syscall.Statfs_t
	if err := syscall.Statfs("/", &stat); err != nil {
		return
	}
	bsize := uint64(stat.Bsize)
	total := (stat.Blocks * bsize) / (1024 * 1024 * 1024)
	free := (stat.Bfree * bsize) / (1024 * 1024 * 1024)
	used := total - free
	pct := 0
	if total > 0 {
		pct = int((used * 100) / total)
	}
	color := "#a6e3a1"
	if pct >= 90 {
		color = "#f38ba8"
	} else if pct >= 70 {
		color = "#f9e2af"
	}
	fmt.Fprintf(os.Stdout, "#[fg=%s]%d/%dGB", color, used, total)
}
