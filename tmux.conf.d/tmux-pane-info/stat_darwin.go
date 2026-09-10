//go:build darwin

package main

import "syscall"

// statMtimeNs returns st's mtime in nanoseconds. Darwin's syscall.Stat_t
// exposes this as the Mtimespec field (Linux uses Mtim instead — see
// stat_linux.go). Field name is the only difference; Timespec.Sec/Nsec are
// int64 on both platforms.
func statMtimeNs(st *syscall.Stat_t) int64 {
	return st.Mtimespec.Sec*1e9 + st.Mtimespec.Nsec
}
