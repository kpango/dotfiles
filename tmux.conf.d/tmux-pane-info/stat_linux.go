//go:build linux

package main

import "syscall"

// statMtimeNs returns st's mtime in nanoseconds. Linux's syscall.Stat_t exposes
// this as the Mtim field (darwin uses Mtimespec instead — see stat_darwin.go).
func statMtimeNs(st *syscall.Stat_t) int64 {
	return st.Mtim.Sec*1e9 + st.Mtim.Nsec
}
