//go:build linux && arm64

package main

import "syscall"

// sysFstatat maps to SYS_FSTATAT (79) on Linux arm64.
const sysFstatat = syscall.SYS_FSTATAT
