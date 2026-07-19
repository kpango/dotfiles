# Pinentry Cancellability and Performance Design

## Overview

This design aims to improve the graceful shutdown capabilities and the execution performance of the `pinentry-tmux` Assuan server. By addressing how cancellation signals are handled and eliminating heap allocations during protocol parsing, we achieve a more robust and secure utility.

## 1. Graceful Cancellation

**Current State:** When the context is cancelled via OS signals (like `SIGINT`), a goroutine calls `os.Exit(1)`. This forcefully terminates the application, bypassing any `defer` statements, which can leave sensitive temporary files on the disk.
**Design:**

- Remove the `os.Exit(1)` call.
- Instead, the background goroutine will call `os.Stdin.Close()` when `ctx.Done()` fires.
- Closing `os.Stdin` will cause the blocking `scanner.Scan()` loop in the server to return `false` immediately.
- The server will gracefully exit its loop, allowing all `defer` statements throughout the call stack to execute and reliably clean up temporary files.

## 2. Zero-Allocation Parsing

**Current State:** The server uses `bufio.Scanner.Text()` and `strings.Cut()` to parse commands. This allocates a new `string` on the heap for every line received from `gpg-agent`.
**Design:**

- Switch the `AssuanServer` loop to use `scanner.Bytes()` and `bytes.Cut()`.
- Update `assuanDecode` and `assuanEncode` to accept and return `[]byte` rather than `string`, eliminating string coercion allocations.
- Replace `strings.ToUpper` with in-place byte comparisons using `bytes.ToUpper` or `bytes.EqualFold`.
- All parsing will execute directly against the `bufio.Scanner`'s internal slice, providing a near-zero allocation profile during the main execution loop.

## Spec Self-Review

- **Placeholders:** None.
- **Consistency:** The changes tightly match the discussed approaches and directly address the stated goals.
- **Scope:** Perfectly scaled for a single implementation plan involving minor edits to `main.go`, `assuan.go`, and `server.go`.
