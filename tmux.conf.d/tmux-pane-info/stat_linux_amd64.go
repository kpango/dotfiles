//go:build linux && amd64

package main

import "syscall"

// sysFstatat maps to SYS_NEWFSTATAT (262) on Linux amd64.
const sysFstatat = syscall.SYS_NEWFSTATAT
