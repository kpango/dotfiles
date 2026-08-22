# Pinentry Cancellability and Performance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement graceful context cancellation by closing `os.Stdin` and remove heap allocations during Assuan protocol parsing.

**Architecture:**

1. Remove `os.Exit(1)` from the `main.go` cancellation goroutine and replace it with `os.Stdin.Close()`.
2. Refactor `assuan.go` decoding functions to operate on `[]byte`.
3. Refactor `server.go` to use `scanner.Bytes()`, `bytes.Cut()`, and `bytes.EqualFold()` instead of string manipulations.

**Tech Stack:** Go 1.26.4

---

### Task 1: Implement Graceful Abort in main.go

**Files:**

- Modify: `pinentry/tmux/main.go`

- [ ] **Step 1: Replace os.Exit with os.Stdin.Close()**

Modify the goroutine in `main.go`:

```go
	go func() {
		<-ctx.Done()
		os.Stdin.Close()
	}()
```

- [ ] **Step 2: Commit**

```bash
git add pinentry/tmux/main.go
git commit -m "fix: gracefully cancel by closing stdin instead of os.Exit"
```

---

### Task 2: Refactor Assuan Helpers to Byte Slices

**Files:**

- Modify: `pinentry/tmux/assuan.go`

- [ ] **Step 1: Update assuanDecode**

Replace `assuanDecode(s string) string` with `assuanDecode(b []byte) string`:

```go
package main

import (
	"bytes"
	"fmt"
	"strconv"
)

func assuanDecode(s []byte) string {
	var b bytes.Buffer
	b.Grow(len(s))
	for i := 0; i < len(s); i++ {
		if s[i] == '%' && i+2 < len(s) {
			hi, e1 := strconv.ParseUint(string(s[i+1:i+2]), 16, 8)
			lo, e2 := strconv.ParseUint(string(s[i+2:i+3]), 16, 8)
			if e1 == nil && e2 == nil {
				b.WriteByte(byte(hi<<4 | lo))
				i += 2
				continue
			}
		}
		b.WriteByte(s[i])
	}
	return b.String()
}

func assuanEncode(s []byte) []byte {
	var b bytes.Buffer
	b.Grow(len(s))
	for i := 0; i < len(s); i++ {
		c := s[i]
		if c < 0x20 || c == '%' || c > 0x7e {
			fmt.Fprintf(&b, "%%%02X", c)
		} else {
			b.WriteByte(c)
		}
	}
	return b.Bytes()
}
```

- [ ] **Step 2: Commit**

```bash
git add pinentry/tmux/assuan.go
git commit -m "perf: migrate assuan helpers to byte slices"
```

---

### Task 3: Implement Zero-Allocation Server Loop

**Files:**

- Modify: `pinentry/tmux/server.go`

- [ ] **Step 1: Refactor scanner loop**

Update `server.go` to use `bytes` instead of `strings`:

```go
package main

import (
	"bufio"
	"bytes"
	"context"
	"fmt"
	"io"
)

type Server struct {
	prompter Prompter
	in       io.Reader
	out      io.Writer
}

func NewServer(p Prompter, in io.Reader, out io.Writer) *Server {
	return &Server{
		prompter: p,
		in:       in,
		out:      out,
	}
}

func (s *Server) Serve(ctx context.Context) {
	w := bufio.NewWriter(s.out)
	send := func(line string) {
		fmt.Fprintln(w, line)
		w.Flush()
	}

	send("OK Pleased to meet you")

	var desc, prompt, errMsg, title string
	prompt = "Passphrase"
	title = "GPG"

	scanner := bufio.NewScanner(s.in)
	space := []byte(" ")
	carriage := []byte("\r")

	for scanner.Scan() {
		line := bytes.TrimRight(scanner.Bytes(), string(carriage))
		cmd, arg, _ := bytes.Cut(line, space)

		if bytes.EqualFold(cmd, []byte("SETDESC")) {
			desc = assuanDecode(arg)
			send("OK")
		} else if bytes.EqualFold(cmd, []byte("SETPROMPT")) {
			prompt = assuanDecode(arg)
			send("OK")
		} else if bytes.EqualFold(cmd, []byte("SETERROR")) {
			errMsg = assuanDecode(arg)
			send("OK")
		} else if bytes.EqualFold(cmd, []byte("SETTITLE")) {
			title = assuanDecode(arg)
			send("OK")
		} else if bytes.EqualFold(cmd, []byte("RESET")) {
			desc = ""
			prompt = "Passphrase"
			errMsg = ""
			title = "GPG"
			send("OK")
		} else if bytes.EqualFold(cmd, []byte("GETPIN")) {
			w.Flush()
			if s.prompter.GetPin(ctx, title, prompt, errMsg) {
				send("OK")
			} else {
				send("ERR 83886179 Operation cancelled")
			}
		} else if bytes.EqualFold(cmd, []byte("CONFIRM")) || bytes.EqualFold(cmd, []byte("MESSAGE")) {
			if s.prompter.Confirm(ctx, desc) {
				send("OK")
			} else {
				send("ERR 277 Operation cancelled")
			}
		} else if bytes.EqualFold(cmd, []byte("BYE")) {
			send("OK closing connection")
			return
		} else {
			send("OK")
		}
	}
}
```

- [ ] **Step 2: Commit**

```bash
git add pinentry/tmux/server.go
git commit -m "perf: zero-allocation parsing in server loop"
```

---

### Task 4: Final Validation

**Files:**

- Test: Build target

- [ ] **Step 1: Run build**

Run: `make pinentry/install`

- [ ] **Step 2: Verify binary exists**

Expected: Compiles cleanly.
