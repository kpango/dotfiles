# Pinentry SOLID Refactoring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor the procedural `pinentry-tmux/main.go` file into a flat, interface-driven package structure following SOLID principles.

**Architecture:** Break `main.go` into `assuan.go` (helpers), `prompter.go` (interface and fallback), `tmux.go` (concrete implementation and popups), and `server.go` (Assuan protocol loop). Update `main.go` to simply wire the dependencies.

**Tech Stack:** Go 1.26.4 (runtimesecret experiment)

---

### Task 1: Create Assuan Helpers

**Files:**

- Create: `pinentry/tmux/assuan.go`
- Modify: `pinentry/tmux/main.go`

- [ ] **Step 1: Extract assuanDecode and assuanEncode**

Create `pinentry/tmux/assuan.go`:

```go
package main

import (
	"fmt"
	"strconv"
	"strings"
)

func assuanDecode(s string) string {
	var b strings.Builder
	b.Grow(len(s))
	for i := 0; i < len(s); i++ {
		if s[i] == '%' && i+2 < len(s) {
			hi, e1 := strconv.ParseUint(s[i+1:i+2], 16, 8)
			lo, e2 := strconv.ParseUint(s[i+2:i+3], 16, 8)
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

func assuanEncode(s string) string {
	var b strings.Builder
	b.Grow(len(s))
	for i := 0; i < len(s); i++ {
		c := s[i]
		if c < 0x20 || c == '%' || c > 0x7e {
			fmt.Fprintf(&b, "%%%02X", c)
		} else {
			b.WriteByte(c)
		}
	}
	return b.String()
}
```

- [ ] **Step 2: Remove helpers from main.go**

Delete `assuanDecode` and `assuanEncode` from `pinentry/tmux/main.go`.

- [ ] **Step 3: Compile check**

Run: `cd pinentry/tmux && GOEXPERIMENT=runtimesecret go build -o /dev/null .`
Expected: Silent success.

- [ ] **Step 4: Commit**

```bash
git add pinentry/tmux/assuan.go pinentry/tmux/main.go
git commit -m "refactor: extract assuan helpers"
```

---

### Task 2: Define Prompter Interface and Fallback

**Files:**

- Create: `pinentry/tmux/prompter.go`
- Modify: `pinentry/tmux/main.go`

- [ ] **Step 1: Create prompter.go**

```go
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
```

- [ ] **Step 2: Remove fallback from main.go**

Delete the `fallback` function from `pinentry/tmux/main.go`.

- [ ] **Step 3: Compile check**

Run: `cd pinentry/tmux && GOEXPERIMENT=runtimesecret go build -o /dev/null .`
Expected: Silent success.

- [ ] **Step 4: Commit**

```bash
git add pinentry/tmux/prompter.go pinentry/tmux/main.go
git commit -m "refactor: define Prompter interface and fallback"
```

---

### Task 3: Extract Tmux Implementation

**Files:**

- Create: `pinentry/tmux/tmux.go`
- Modify: `pinentry/tmux/main.go`

- [ ] **Step 1: Create tmux.go**

Extract the Tmux and Temp File logic from `main.go`.

```go
package main

import (
	"context"
	"os"
	"os/exec"
	"runtime/secret"
	"strconv"
	"strings"
	"syscall"
)

// temp file helpers

func tmpDir() string {
	if d := os.Getenv("XDG_RUNTIME_DIR"); d != "" {
		return d
	}
	if d := os.Getenv("TMPDIR"); d != "" {
		return d
	}
	return "/tmp"
}

func makeTempFile() (*os.File, error) {
	old := syscall.Umask(0o077)
	defer syscall.Umask(old)
	return os.CreateTemp(tmpDir(), ".pin-")
}

func zeroAndRemove(path string) {
	if path == "" {
		return
	}
	if f, err := os.OpenFile(path, os.O_WRONLY|os.O_TRUNC, 0o600); err == nil {
		f.Close()
	}
	os.Remove(path)
}

// tmuxPrompter implements Prompter

type tmuxPrompter struct {
	sock string
}

func newTmuxPrompter(ctx context.Context) *tmuxPrompter {
	trySock := func(s string) string {
		s, _, _ = strings.Cut(s, ",")
		if s == "" {
			return ""
		}
		if fi, err := os.Stat(s); err == nil && (fi.Mode()&os.ModeSocket != 0) {
			return s
		}
		return ""
	}

	var sock string
	if s := trySock(os.Getenv("TMUX")); s != "" {
		sock = s
	} else {
		for _, field := range strings.Fields(os.Getenv("PINENTRY_USER_DATA")) {
			if v, ok := strings.CutPrefix(field, "TMUX="); ok {
				if s := trySock(v); s != "" {
					sock = s
					break
				}
			}
		}
	}

	if sock == "" {
		return nil
	}

	out, err := exec.CommandContext(ctx, "tmux", "-S", sock, "-V").Output()
	if err != nil {
		return nil
	}
	ver := strings.TrimSpace(string(out))
	if idx := strings.LastIndex(ver, " "); idx >= 0 {
		ver = ver[idx+1:]
	}
	parts := strings.SplitN(ver, ".", 2)
	if len(parts) < 2 {
		return nil
	}
	minStr := parts[1]
	for i, c := range minStr {
		if c < '0' || c > '9' {
			minStr = minStr[:i]
			break
		}
	}
	maj, e1 := strconv.Atoi(parts[0])
	min, e2 := strconv.Atoi(minStr)
	if e1 != nil || e2 != nil || !(maj > 3 || (maj == 3 && min >= 2)) {
		return nil
	}

	return &tmuxPrompter{sock: sock}
}

func (p *tmuxPrompter) GetPin(ctx context.Context, title, prompt, errMsg string) bool {
	pinFile, err := makeTempFile()
	if err != nil {
		return false
	}
	pinPath := pinFile.Name()
	pinFile.Close()

	stFile, err := makeTempFile()
	if err != nil {
		os.Remove(pinPath)
		return false
	}
	stPath := stFile.Name()
	stFile.Close()

	defer func() {
		zeroAndRemove(pinPath)
		os.Remove(stPath)
	}()

	const zshScript = `emulate zsh
[[ -n "$3" ]] && print -r -- "\nError: $3"
print -r -- "${1:+\n$1}"
print
read -rs "?$2: " _p
print
print -n "$_p" > "$4"
printf OK > "$5"`

	_ = exec.CommandContext(ctx, "tmux", "-S", p.sock, "popup", "-E", "-w", "72", "-h", "10",
		"--", "zsh", "-c", zshScript, "--",
		title, prompt, errMsg, pinPath, stPath).Run()

	stBytes, _ := os.ReadFile(stPath)
	ok := strings.TrimSpace(string(stBytes)) == "OK"
	clear(stBytes)

	if !ok {
		return false
	}

	secret.Do(func() {
		var pinBuf [512]byte
		f, err := os.Open(pinPath)
		if err != nil {
			return
		}
		n, _ := f.Read(pinBuf[:])
		f.Close()

		_ = syscall.Mlock(pinBuf[:])
		defer syscall.Munlock(pinBuf[:])

		var encBuf [2048]byte
		encLen := 0
		encBuf[encLen] = 'D'
		encLen++
		encBuf[encLen] = ' '
		encLen++

		const hex = "0123456789ABCDEF"
		for i := 0; i < n; i++ {
			c := pinBuf[i]
			if c < 0x20 || c == '%' || c > 0x7e {
				encBuf[encLen] = '%'
				encLen++
				encBuf[encLen] = hex[c>>4]
				encLen++
				encBuf[encLen] = hex[c&0xF]
				encLen++
			} else {
				encBuf[encLen] = c
				encLen++
			}
		}
		encBuf[encLen] = '\n'
		encLen++

		os.Stdout.Write(encBuf[:encLen])
	})

	return true
}

func (p *tmuxPrompter) Confirm(ctx context.Context, desc string) bool {
	stFile, err := makeTempFile()
	if err != nil {
		return true
	}
	stPath := stFile.Name()
	stFile.Close()
	defer os.Remove(stPath)

	const zshScript = `emulate zsh
print -r -- "\n$1\n"
read -r "?[Enter] confirm  [q] cancel: " _a
[[ "$_a" == q* ]] && printf CANCEL > "$2" || printf OK > "$2"`

	_ = exec.CommandContext(ctx, "tmux", "-S", p.sock, "popup", "-E", "-w", "72", "-h", "8",
		"--", "zsh", "-c", zshScript, "--",
		desc, stPath).Run()

	stBytes, _ := os.ReadFile(stPath)
	return strings.TrimSpace(string(stBytes)) == "OK"
}
```

- [ ] **Step 2: Delete logic from main.go**

Delete `findSock`, `checkTmuxVersion`, `tmpDir`, `makeTempFile`, `zeroAndRemove`, `(s *state) getPin`, and `(s *state) confirm` from `main.go`.

- [ ] **Step 3: Compile check**

Ignore compilation errors for now as `main.go` is in a broken intermediate state.

- [ ] **Step 4: Commit**

```bash
git add pinentry/tmux/tmux.go pinentry/tmux/main.go
git commit -m "refactor: extract tmux and temp file logic"
```

---

### Task 4: Extract Server and Update Main

**Files:**

- Create: `pinentry/tmux/server.go`
- Modify: `pinentry/tmux/main.go`

- [ ] **Step 1: Create server.go**

```go
package main

import (
	"bufio"
	"context"
	"fmt"
	"io"
	"strings"
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
	for scanner.Scan() {
		line := strings.TrimRight(scanner.Text(), "\r")
		cmd, arg, _ := strings.Cut(line, " ")

		switch strings.ToUpper(cmd) {
		case "SETDESC":
			desc = assuanDecode(arg)
			send("OK")
		case "SETPROMPT":
			prompt = assuanDecode(arg)
			send("OK")
		case "SETERROR":
			errMsg = assuanDecode(arg)
			send("OK")
		case "SETTITLE":
			title = assuanDecode(arg)
			send("OK")
		case "RESET":
			desc = ""
			prompt = "Passphrase"
			errMsg = ""
			title = "GPG"
			send("OK")
		case "GETPIN":
			w.Flush()
			if s.prompter.GetPin(ctx, title, prompt, errMsg) {
				send("OK")
			} else {
				send("ERR 83886179 Operation cancelled")
			}
		case "CONFIRM", "MESSAGE":
			if s.prompter.Confirm(ctx, desc) {
				send("OK")
			} else {
				send("ERR 277 Operation cancelled")
			}
		case "BYE":
			send("OK closing connection")
			return
		default:
			send("OK")
		}
	}
}
```

- [ ] **Step 2: Update main.go**

Replace the entirety of `pinentry/tmux/main.go` with:

```go
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
		os.Exit(1)
	}()

	prompter := newTmuxPrompter(ctx)
	if prompter == nil {
		fallback(os.Args[1:])
		return
	}

	server := NewServer(prompter, os.Stdin, os.Stdout)
	server.Serve(ctx)
}
```

- [ ] **Step 3: Compile check**

Run: `cd pinentry/tmux && GOEXPERIMENT=runtimesecret go build -o /dev/null .`
Expected: Silent success.

- [ ] **Step 4: Commit**

```bash
git add pinentry/tmux/server.go pinentry/tmux/main.go
git commit -m "refactor: implement assuan server and update main"
```

---

### Task 5: Final Validation

**Files:**

- Test: Build target

- [ ] **Step 1: Run build**

Run: `make pinentry/install`

- [ ] **Step 2: Verify binary exists**

Expected: Compiles cleanly and installs correctly.
