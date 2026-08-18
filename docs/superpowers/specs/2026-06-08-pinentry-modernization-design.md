# Pinentry Go Modernization Design

## Architecture / Changes

The existing Go implementation of `pinentry-tmux` will be refactored to align with Go 1.26.4 standards. This includes utilizing experimental secure memory features where available and leveraging modern standard library functions for improved security and code style.

## Key Upgrades

1. **Memory Zeroing:** Replaced manual loops with the built-in `clear()` function (Go 1.21+) to zero out passphrase memory buffers.
2. **Secure Execution:** Adopted the experimental `runtime/secret` package (via `GOEXPERIMENT=runtimesecret`) to execute sensitive operations (`secret.Do()`) ensuring that stack frames and registers handling the passphrase are wiped correctly upon completion.
3. **Signal Management:** Transitioned to `signal.NotifyContext` (Go 1.16+) for graceful shutdown and context-driven lifecycle control.
4. **Subprocess Control:** Upgraded from `exec.Command` to `exec.CommandContext`, ensuring spawned tmux popup processes are immediately terminated if the parent pinentry receives a cancellation signal.
5. **String Utilities:** Adopted `strings.CutPrefix` (Go 1.20+) and other modern string functions to streamline prefix parsing.
6. **Temp File Security:** Implemented robust closure patterns and deferred cleanups to guarantee temporary files (e.g., those passed to tmux popups) are quickly zeroed out and removed.

## Steps

1. Refactor `pinentry/tmux/main.go` using the design aspects listed above.
2. Update the build commands in `Makefile.d/install.mk` to include the `GOEXPERIMENT=runtimesecret` build constraint.

## Testing

- Verify that `make pinentry/install` compiles without issues using the `runtimesecret` experiment.
- Ensure that the resulting `pinentry-tmux` binary runs and securely wipes its memory when invoked.
