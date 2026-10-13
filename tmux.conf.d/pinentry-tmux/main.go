// pinentry-tmux: GPG pinentry via tmux popup; falls back to pinentry-tty.
// Implements the Assuan protocol subset used by gpg-agent.
package main

import (
	"context"
	"os"
	"os/signal"
	"syscall"
)

func main() {
	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM, syscall.SIGHUP)
	defer cancel()

	go func() {
		<-ctx.Done()
		os.Stdin.Close()
	}()

	prompter := newTmuxPrompter(ctx)
	if prompter == nil {
		fallback(os.Args[1:])
		return
	}

	server := NewServer(prompter, os.Stdin, os.Stdout)
	server.Serve(ctx)
}
