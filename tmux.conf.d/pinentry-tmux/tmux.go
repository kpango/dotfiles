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

	f, err := os.Open(pinPath)
	if err != nil {
		return false
	}
	defer f.Close()

	secret.Do(func() {
		var pinBuf [512]byte
		n, err := f.Read(pinBuf[:])
		if err != nil || n == 0 {
			return
		}

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
