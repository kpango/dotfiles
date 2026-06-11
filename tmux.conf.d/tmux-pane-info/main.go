// tmux-pane-info: fast replacement for tmux-status-left, tmux-status-branch,
// tmux-short-path, and tmux-kube zsh scripts.
//
// Usage:
//
//	tmux-pane-info path   <dir>             → abbreviated path
//	tmux-pane-info branch <dir>             → " branchname" or ""
//	tmux-pane-info pane   <dir>             → complete path+branch coloured segment
//	tmux-pane-info kube   [ctx_fg] [ns_fg]  → tmux colour-coded kube segment
//
// Shared cache: ~/.cache/tmux-pane-info
//
//	line 1: key = "dir:HEAD_mtime_ns"
//	line 2: abbreviated path
//	line 3: branch (" main" / " abc1234" / "")
//
// Hot path (cache hit): raw syscalls only — go-git is never invoked.
// Cold path (cache miss): go-git resolves the branch name.
// Kubernetes info uses k8s client-go instead of an external kubectl process.
package main

import (
	"bytes"
	"os"
	"strconv"
	"syscall"
	"unicode/utf8"

	gogit "github.com/go-git/go-git/v5"
	"k8s.io/client-go/tools/clientcmd"
)

var (
	homeDir       string
	cacheDir      string
	cacheFilePath string
	kubeCachePath string
	cachePathNT   []byte // null-terminated cacheFilePath for openBuf
	kubePathNT    []byte // null-terminated kubeCachePath for openBuf
	pidSuffix     string // ".tmp.<pid>" precomputed for atomic writes
)

var gitdirPrefix = []byte("gitdir: ")

func init() {
	homeDir, _ = os.UserHomeDir()
	base := homeDir + "/.cache"
	if d := os.Getenv("XDG_CACHE_HOME"); d != "" {
		base = d
	}
	cacheDir = base
	cacheFilePath = base + "/tmux-pane-info"
	kubeCachePath = base + "/tmux-kube-out"
	cachePathNT = append([]byte(cacheFilePath), 0)
	kubePathNT = append([]byte(kubeCachePath), 0)

	var buf [32]byte
	b := append(buf[:0], ".tmp."...)
	b = strconv.AppendInt(b, int64(os.Getpid()), 10)
	pidSuffix = string(b)
}

// statBuf stats the path given as a null-terminated byte slice.
// Uses syscall.Stat which dispatches the correct syscall per architecture
// (SYS_STAT on amd64, SYS_FSTATAT on arm64).
func statBuf(path []byte, st *syscall.Stat_t) syscall.Errno {
	if err := syscall.Stat(string(path[:len(path)-1]), st); err != nil {
		return err.(syscall.Errno)
	}
	return 0
}

// openBuf opens the path given as a null-terminated byte slice.
// Uses syscall.Open which dispatches the correct syscall per architecture
// (SYS_OPEN on amd64, SYS_OPENAT on arm64).
func openBuf(path []byte, flags int) (int, syscall.Errno) {
	fd, err := syscall.Open(string(path[:len(path)-1]), flags, 0)
	if err != nil {
		return -1, err.(syscall.Errno)
	}
	return fd, 0
}

func main() {
	if len(os.Args) < 2 {
		os.Stdout.WriteString(".")
		return
	}
	switch os.Args[1] {
	case "branch":
		dir := ""
		if len(os.Args) >= 3 {
			dir = os.Args[2]
		}
		paneOut(dir, true)

	case "pane":
		// Single call that outputs the complete path+branch coloured segment.
		dir := "."
		if len(os.Args) >= 3 {
			dir = os.Args[2]
		}
		paneSegment(dir)

	case "kube":
		ctxFg, nsFg := "green", "brightcyan"
		if len(os.Args) > 2 {
			ctxFg = os.Args[2]
		}
		if len(os.Args) > 3 {
			nsFg = os.Args[3]
		}
		os.Stdout.WriteString(kubeSegment(ctxFg, nsFg))

	default: // "path" or any unrecognised subcommand
		dir := "."
		if len(os.Args) >= 3 {
			dir = os.Args[2]
		}
		paneOut(dir, false)
	}
}

// paneOut computes (or reads from cache) the abbreviated path and branch for
// dir, then writes the requested field to stdout.
func paneOut(dir string, wantBranch bool) {
	switch dir {
	case "", ".":
		if wd, err := os.Getwd(); err == nil {
			dir = wd
		} else {
			dir = "."
		}
	case "/":
		if !wantBranch {
			os.Stdout.WriteString("/")
		}
		return
	}

	headPath, headMtime := findGitHeadPath(dir)

	var keyBuf [512]byte
	key := keyBuf[:0]
	key = append(key, dir...)
	key = append(key, ':')
	key = strconv.AppendInt(key, headMtime, 10)

	if readCacheToStdout(key, wantBranch) {
		return
	}

	sp := abbreviatePath(dir)
	br := branchFromGoGit(dir, headPath)

	writePaneCache(key, sp, br)

	if wantBranch {
		os.Stdout.Write(br)
	} else {
		os.Stdout.Write(sp)
	}
}

// plRight is the Powerline right-pointing solid triangle (U+E0B0).
// Hardcoded so the Go binary controls separator rendering rather than relying
// on tmux user-option expansion inside #(…) output.
const plRight = ""

// paneSegment outputs the complete path+branch tmux colour segment for dir in
// a single call, replacing the three separate path/branch invocations that the
// old status-left format required.
func paneSegment(dir string) {
	switch dir {
	case "", ".":
		if wd, err := os.Getwd(); err == nil {
			dir = wd
		} else {
			dir = "."
		}
	case "/":
		os.Stdout.WriteString("#[fg=#89dceb,bg=#313244]/ #[fg=#313244,bg=#1e1e2e,nobold]" + plRight)
		return
	}

	headPath, headMtime := findGitHeadPath(dir)

	var keyBuf [512]byte
	key := keyBuf[:0]
	key = append(key, dir...)
	key = append(key, ':')
	key = strconv.AppendInt(key, headMtime, 10)

	if paneSegmentFromCache(key) {
		return
	}

	sp := abbreviatePath(dir)
	br := branchFromGoGit(dir, headPath)

	writePaneCache(key, sp, br)
	writeSegment(sp, br)
}

// ── git helpers ──────────────────────────────────────────────────────────────

// findGitHeadPath walks up from dir using raw syscalls to locate the .git/HEAD
// file. Returns its path and mtime nanoseconds. Used on every call for the
// cache key — raw syscalls keep this allocation-free on cache hit.
func findGitHeadPath(dir string) (headPath string, mtimeNs int64) {
	// PATH_MAX(4096) + "/.git/HEAD\0"(11) = 4107; round to 4112.
	var buf [4112]byte
	var st syscall.Stat_t
	d := dir
	for {
		dn := copy(buf[:], d)
		if dn+11 > len(buf) {
			break
		}
		buf[dn] = '/'
		buf[dn+1] = '.'
		buf[dn+2] = 'g'
		buf[dn+3] = 'i'
		buf[dn+4] = 't'
		buf[dn+5] = 0

		if errno := statBuf(buf[:dn+6], &st); errno == 0 {
			if st.Mode&syscall.S_IFMT == syscall.S_IFDIR {
				// Normal .git dir: HEAD is at d/.git/HEAD
				buf[dn+5] = '/'
				buf[dn+6] = 'H'
				buf[dn+7] = 'E'
				buf[dn+8] = 'A'
				buf[dn+9] = 'D'
				buf[dn+10] = 0
				var hst syscall.Stat_t
				if errno2 := statBuf(buf[:dn+11], &hst); errno2 == 0 {
					hp := string(buf[:dn+10])
					return hp, hst.Mtim.Sec*1e9 + hst.Mtim.Nsec
				}
			} else {
				// gitfile: "gitdir: <path>" — submodule or git worktree
				fd, errno2 := openBuf(buf[:dn+6], syscall.O_RDONLY)
				if errno2 == 0 {
					var raw [512]byte
					n, _ := syscall.Read(fd, raw[:])
					syscall.Close(fd)
					line := bytes.TrimSpace(raw[:n])
					line = bytes.TrimPrefix(line, gitdirPrefix)
					gd := string(line)
					if len(gd) == 0 || gd[0] != '/' {
						gd = d + "/" + gd
					}
					hp := gd + "/HEAD"
					var hst syscall.Stat_t
					if syscall.Stat(hp, &hst) == nil {
						return hp, hst.Mtim.Sec*1e9 + hst.Mtim.Nsec
					}
				}
			}
			return "", 0
		}
		parent := parentDir(d)
		if parent == d {
			break
		}
		d = parent
	}
	return "", 0
}

// parentDir returns the parent directory of d without allocating via filepath.Dir.
func parentDir(d string) string {
	if d == "/" {
		return d
	}
	i := len(d) - 1
	for i > 0 && d[i] == '/' {
		i--
	}
	for i > 0 && d[i] != '/' {
		i--
	}
	if i == 0 {
		return "/"
	}
	return d[:i]
}

// gitRootFromHeadPath derives the worktree root from a HEAD file path for a
// normal repository (headPath ends with "/.git/HEAD"). Returns "" for
// worktrees and submodules whose HEAD lives outside the worktree.
func gitRootFromHeadPath(headPath string) string {
	const suffix = "/.git/HEAD"
	if len(headPath) > len(suffix) && headPath[len(headPath)-len(suffix):] == suffix {
		return headPath[:len(headPath)-len(suffix)]
	}
	return ""
}

// branchFromGoGit opens the repository using go-git and returns the current
// branch name or short commit hash. Called only on cache miss.
//
// For normal repos: PlainOpen(gitRoot) — no directory walk needed.
// For submodules/worktrees: PlainOpenWithOptions(dir, DetectDotGit) as fallback.
func branchFromGoGit(dir, headPath string) []byte {
	var repo *gogit.Repository

	if root := gitRootFromHeadPath(headPath); root != "" {
		var err error
		repo, err = gogit.PlainOpen(root)
		if err != nil {
			repo = nil
		}
	}
	if repo == nil && dir != "" {
		var err error
		repo, err = gogit.PlainOpenWithOptions(dir, &gogit.PlainOpenOptions{
			DetectDotGit:          true,
			EnableDotGitCommonDir: true,
		})
		if err != nil {
			return nil
		}
	}
	return branchFromRepo(repo)
}

// branchFromRepo reads the current branch name (or short commit hash on
// detached HEAD) from an open go-git Repository.
// Returned slice has a leading space: e.g. " main" or " abc1234".
func branchFromRepo(repo *gogit.Repository) []byte {
	if repo == nil {
		return nil
	}
	ref, err := repo.Head()
	if err != nil {
		return nil
	}

	var name string
	if ref.Name().IsBranch() {
		name = ref.Name().Short()
	} else {
		h := ref.Hash().String()
		if len(h) > 7 {
			h = h[:7]
		}
		name = h
	}
	if name == "" {
		return nil
	}
	out := make([]byte, 1+len(name))
	out[0] = ' '
	copy(out[1:], name)
	return out
}

// ── path helpers ─────────────────────────────────────────────────────────────

// abbreviatePath replaces $HOME with ~ and abbreviates every path component
// before the last one to its first Unicode rune. Returns []byte.
func abbreviatePath(dir string) []byte {
	var p string
	if dir == homeDir {
		return []byte("~")
	} else if len(dir) > len(homeDir) && dir[:len(homeDir)] == homeDir && dir[len(homeDir)] == '/' {
		p = "~" + dir[len(homeDir):]
	} else {
		p = dir
	}

	out := make([]byte, 0, len(p)/2+8)

	lastSlash := -1
	for i := len(p) - 1; i >= 0; i-- {
		if p[i] == '/' {
			lastSlash = i
			break
		}
	}
	if lastSlash <= 0 {
		return []byte(p)
	}

	i := 0
	for i < len(p) {
		if p[i] == '/' {
			out = append(out, '/')
			i++
			continue
		}
		end := i
		for end < len(p) && p[end] != '/' {
			end++
		}
		if i > lastSlash {
			out = append(out, p[i:end]...)
			i = end
			continue
		}
		seg := p[i:end]
		if seg == "~" {
			out = append(out, '~')
		} else {
			_, size := utf8.DecodeRuneInString(seg)
			out = append(out, seg[:size]...)
		}
		i = end
	}
	return out
}

// ── cache helpers ─────────────────────────────────────────────────────────────

// readCacheToStdout reads the cache file into a stack buffer, checks the key,
// and writes the requested field directly to stdout.
// Returns true on cache hit. Uses openBuf for zero-alloc file open.
func readCacheToStdout(key []byte, wantBranch bool) bool {
	fd, errno := openBuf(cachePathNT, syscall.O_RDONLY)
	if errno != 0 {
		return false
	}
	var buf [1024]byte
	n, _ := syscall.Read(fd, buf[:])
	syscall.Close(fd)

	data := buf[:n]

	nl1 := bytes.IndexByte(data, '\n')
	if nl1 < 0 {
		return false
	}
	if !bytes.Equal(data[:nl1], key) {
		return false
	}

	rest := data[nl1+1:]

	nl2 := bytes.IndexByte(rest, '\n')
	if nl2 < 0 {
		return false
	}
	spSlice := rest[:nl2]
	brSlice := rest[nl2+1:]
	if i := bytes.IndexByte(brSlice, '\n'); i >= 0 {
		brSlice = brSlice[:i]
	}

	if wantBranch {
		os.Stdout.Write(brSlice)
	} else {
		os.Stdout.Write(spSlice)
	}
	return true
}

// paneSegmentFromCache reads the cache file, verifies the key, then writes the
// full coloured segment to stdout. Returns true on cache hit.
func paneSegmentFromCache(key []byte) bool {
	fd, errno := openBuf(cachePathNT, syscall.O_RDONLY)
	if errno != 0 {
		return false
	}
	var buf [1024]byte
	n, _ := syscall.Read(fd, buf[:])
	syscall.Close(fd)

	data := buf[:n]
	nl1 := bytes.IndexByte(data, '\n')
	if nl1 < 0 || !bytes.Equal(data[:nl1], key) {
		return false
	}
	rest := data[nl1+1:]
	nl2 := bytes.IndexByte(rest, '\n')
	if nl2 < 0 {
		return false
	}
	sp := rest[:nl2]
	br := rest[nl2+1:]
	if i := bytes.IndexByte(br, '\n'); i >= 0 {
		br = br[:i]
	}
	writeSegment(sp, br)
	return true
}

// writeSegment formats and writes the path+branch coloured tmux segment.
// sp is the abbreviated path; br is the branch with a leading space (e.g. " main"),
// or nil/empty for non-git directories.
func writeSegment(sp, br []byte) {
	out := make([]byte, 0, 96+len(sp)+len(br))
	out = append(out, "#[fg=#89dceb,bg=#313244]"...)
	out = append(out, sp...)
	if len(br) > 0 {
		out = append(out, " #[fg=#313244,bg=#45475a,nobold]"...)
		out = append(out, plRight...)
		out = append(out, "#[fg=#cba6f7,bg=#45475a,bold]"...)
		out = append(out, br...) // br already has a leading space
		out = append(out, " #[fg=#45475a,bg=#1e1e2e,nobold]"...)
		out = append(out, plRight...)
	} else {
		out = append(out, " #[fg=#313244,bg=#1e1e2e,nobold]"...)
		out = append(out, plRight...)
	}
	os.Stdout.Write(out)
}

// writePaneCache writes key, sp, and br to the cache file atomically via rename.
func writePaneCache(key, sp, br []byte) {
	_ = os.MkdirAll(cacheDir, 0o755)
	tmp := cacheFilePath + pidSuffix

	content := make([]byte, 0, len(key)+1+len(sp)+1+len(br)+1)
	content = append(content, key...)
	content = append(content, '\n')
	content = append(content, sp...)
	content = append(content, '\n')
	content = append(content, br...)
	content = append(content, '\n')

	if err := os.WriteFile(tmp, content, 0o644); err == nil {
		os.Rename(tmp, cacheFilePath) //nolint:errcheck — best-effort atomic write
	}
}

// ── kubernetes segment ───────────────────────────────────────────────────────

// kubeSegment returns a tmux-coloured kubernetes context:namespace string.
// Config is loaded via k8s client-go (no external kubectl invocation).
func kubeSegment(ctxFg, nsFg string) string {
	rules := clientcmd.NewDefaultClientConfigLoadingRules()

	if kubeCacheValid(rules.Precedence) {
		fd, errno := openBuf(kubePathNT, syscall.O_RDONLY)
		if errno == 0 {
			var buf [512]byte
			n, _ := syscall.Read(fd, buf[:])
			syscall.Close(fd)
			data := buf[:n]
			for len(data) > 0 && data[len(data)-1] == '\n' {
				data = data[:len(data)-1]
			}
			if len(data) > 0 {
				return string(data)
			}
		}
	}

	rawConfig, err := rules.Load()
	if err != nil || rawConfig.CurrentContext == "" {
		return ""
	}

	ctx := rawConfig.CurrentContext
	ns := "default"
	if ctxInfo, ok := rawConfig.Contexts[ctx]; ok && ctxInfo != nil && ctxInfo.Namespace != "" {
		ns = ctxInfo.Namespace
	}

	out := "#[fg=blue]⎈ #[fg=" + ctxFg + "]" + ctx + "#[fg=colour250]:#[fg=" + nsFg + "]" + ns

	_ = os.MkdirAll(cacheDir, 0o755)
	tmp := kubeCachePath + pidSuffix
	if err := os.WriteFile(tmp, []byte(out+"\n"), 0o644); err == nil {
		os.Rename(tmp, kubeCachePath) //nolint:errcheck
	}
	return out
}

// kubeCacheValid checks whether the kube cache is newer than all source configs.
func kubeCacheValid(sources []string) bool {
	var cst syscall.Stat_t
	if statBuf(kubePathNT, &cst) != 0 {
		return false
	}
	cacheMtime := cst.Mtim.Sec*1e9 + cst.Mtim.Nsec
	for _, src := range sources {
		var sst syscall.Stat_t
		if syscall.Stat(src, &sst) == nil {
			if sst.Mtim.Sec*1e9+sst.Mtim.Nsec > cacheMtime {
				return false
			}
		}
	}
	return true
}
