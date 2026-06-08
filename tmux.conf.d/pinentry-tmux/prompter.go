package main

import (
	"context"
	"fmt"
	"os"
	"syscall"
)

type Prompter interface {
	GetPin(ctx context.Context, title, prompt, errMsg string) bool
	Confirm(ctx context.Context, desc string) bool
}

func fallback(args []string) {
	fb := os.Getenv("PINENTRY_TMUX_FALLBACK")
	if fb == "" {
		fb = "/usr/bin/pinentry-tty"
	}
	if err := syscall.Exec(fb, append([]string{fb}, args...), os.Environ()); err != nil {
		fmt.Fprintf(os.Stderr, "pinentry-tmux: exec %s: %v\n", fb, err)
		os.Exit(1)
	}
}
