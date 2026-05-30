// pinentry-tmux: GPG pinentry via tmux popup; falls back to pinentry-tty.
// Implements the Assuan protocol subset used by gpg-agent.
package main

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
)

// pinBuf holds the passphrase; locked into RAM in init() to prevent swap.
var pinBuf [512]byte

func init() {
	// Best-effort: mlock the passphrase buffer so it never swaps to disk.
	_ = syscall.Mlock(pinBuf[:])
}

// ── Assuan helpers ────────────────────────────────────────────────────────────

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

// ── tmux socket resolution ────────────────────────────────────────────────────

func findSock() string {
	trySock := func(s string) string {
		if idx := strings.IndexByte(s, ','); idx >= 0 {
			s = s[:idx]
		}
		if s == "" {
			return ""
		}
		if fi, err := os.Stat(s); err == nil && (fi.Mode()&os.ModeSocket != 0) {
			return s
		}
		return ""
	}

	if sock := trySock(os.Getenv("TMUX")); sock != "" {
		return sock
	}
	for _, field := range strings.Fields(os.Getenv("PINENTRY_USER_DATA")) {
		if strings.HasPrefix(field, "TMUX=") {
			if sock := trySock(strings.TrimPrefix(field, "TMUX=")); sock != "" {
				return sock
			}
		}
	}
	return ""
}

func checkTmuxVersion(sock string) bool {
	out, err := exec.Command("tmux", "-S", sock, "-V").Output()
	if err != nil {
		return false
	}
	ver := strings.TrimSpace(string(out))
	if idx := strings.LastIndex(ver, " "); idx >= 0 {
		ver = ver[idx+1:]
	}
	parts := strings.SplitN(ver, ".", 2)
	if len(parts) < 2 {
		return false
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
	if e1 != nil || e2 != nil {
		return false
	}
	return maj > 3 || (maj == 3 && min >= 2)
}

// ── Fallback ──────────────────────────────────────────────────────────────────

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

// ── Temp file helpers ─────────────────────────────────────────────────────────

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
	f, err := os.CreateTemp(tmpDir(), ".pin-")
	syscall.Umask(old)
	return f, err
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

// ── Protocol state ────────────────────────────────────────────────────────────

type state struct {
	desc   string
	prompt string
	errMsg string
	title  string
}

func newState() state {
	return state{prompt: "Passphrase", title: "GPG"}
}

// ── tmux popup actions ────────────────────────────────────────────────────────

func (s *state) getPin(sock string) (string, bool) {
	pinFile, err := makeTempFile()
	if err != nil {
		return "", false
	}
	pinPath := pinFile.Name()
	pinFile.Close()

	stFile, err := makeTempFile()
	if err != nil {
		os.Remove(pinPath)
		return "", false
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

	_ = exec.Command("tmux", "-S", sock, "popup", "-E", "-w", "72", "-h", "10",
		"--", "zsh", "-c", zshScript, "--",
		s.title, s.prompt, s.errMsg, pinPath, stPath).Run()

	stBytes, _ := os.ReadFile(stPath)
	ok := strings.TrimSpace(string(stBytes)) == "OK"
	for i := range stBytes {
		stBytes[i] = 0
	}

	if !ok {
		return "", false
	}

	pinBytes, _ := os.ReadFile(pinPath)
	n := copy(pinBuf[:], pinBytes)
	pin := string(pinBuf[:n])
	for i := range pinBytes {
		pinBytes[i] = 0
	}
	for i := range pinBuf {
		pinBuf[i] = 0
	}
	return pin, true
}

func (s *state) confirm(sock string) bool {
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

	_ = exec.Command("tmux", "-S", sock, "popup", "-E", "-w", "72", "-h", "8",
		"--", "zsh", "-c", zshScript, "--",
		s.desc, stPath).Run()

	stBytes, _ := os.ReadFile(stPath)
	return strings.TrimSpace(string(stBytes)) == "OK"
}

// ── Main loop ─────────────────────────────────────────────────────────────────

func main() {
	sock := findSock()
	if sock == "" || !checkTmuxVersion(sock) {
		fallback(os.Args[1:])
		return
	}

	sigs := make(chan os.Signal, 1)
	signal.Notify(sigs, syscall.SIGINT, syscall.SIGTERM, syscall.SIGHUP)
	go func() {
		<-sigs
		for i := range pinBuf {
			pinBuf[i] = 0
		}
		os.Exit(1)
	}()
	defer func() {
		for i := range pinBuf {
			pinBuf[i] = 0
		}
	}()

	w := bufio.NewWriter(os.Stdout)
	send := func(line string) {
		fmt.Fprintln(w, line)
		w.Flush()
	}

	send("OK Pleased to meet you")

	st := newState()
	scanner := bufio.NewScanner(os.Stdin)
	for scanner.Scan() {
		line := strings.TrimRight(scanner.Text(), "\r")
		cmd, arg, _ := strings.Cut(line, " ")

		switch strings.ToUpper(cmd) {
		case "SETDESC":
			st.desc = assuanDecode(arg)
			send("OK")
		case "SETPROMPT":
			st.prompt = assuanDecode(arg)
			send("OK")
		case "SETERROR":
			st.errMsg = assuanDecode(arg)
			send("OK")
		case "SETTITLE":
			st.title = assuanDecode(arg)
			send("OK")
		case "RESET":
			st = newState()
			send("OK")
		case "GETPIN":
			pin, ok := st.getPin(sock)
			if ok {
				send("D " + assuanEncode(pin))
				send("OK")
			} else {
				send("ERR 83886179 Operation cancelled")
			}
		case "CONFIRM", "MESSAGE":
			if st.confirm(sock) {
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
