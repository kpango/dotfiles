// tmux-pane-info: fast replacement for tmux-status-left, tmux-status-branch,
// tmux-short-path, and tmux-kube zsh scripts.
//
// Usage:
//
//	tmux-pane-info path   <dir>             → abbreviated path
//	tmux-pane-info branch <dir>             → " branchname" or ""
//	tmux-pane-info pane   <dir>             → complete path+branch coloured segment
//	tmux-pane-info kube   [ctx_fg] [ns_fg]  → tmux colour-coded kube segment
//	tmux-pane-info disk                     → tmux colour-coded disk usage segment
//	tmux-pane-info right                    → complete right status bar (CPU/RAM/GPU/VOL/kube)
//
// Per-directory cache: ~/.cache/tmux-pane-info.<fnv32hex>
//
//	line 1: key = "dir:HEAD_mtime_ns"
//	line 2: abbreviated path
//	line 3: branch (" main" / " abc1234" / "")
//
// Each directory gets its own cache file so concurrent tmux sessions with
// different active pane paths do not thrash each other's cache, which would
// cause go-git cold-path invocations and blank status-left output.
//
// Hot path (cache hit): raw syscalls only — go-git is never invoked.
// Cold path (cache miss): go-git resolves the branch name.
// Kubernetes info uses k8s client-go instead of an external kubectl process.
package main

import (
	"bytes"
	"hash/fnv"
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
	cacheFilePath string // base path; actual cache = cacheFilePath + "." + fnv32hex(dir)
	kubeCachePath string
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
	kubePathNT = append([]byte(kubeCachePath), 0)

	var buf [32]byte
	b := append(buf[:0], ".tmp."...)
	b = strconv.AppendInt(b, int64(os.Getpid()), 10)
	pidSuffix = string(b)
}

// cachePathForDir returns the cache file path and its null-terminated form for
// dir. Each directory maps to its own file via FNV-32a so that concurrent tmux
// sessions with different active pane paths never overwrite each other's cache.
func cachePathForDir(dir string) (path string, nt []byte) {
	h := fnv.New32a()
	h.Write([]byte(dir))
	path = cacheFilePath + "." + strconv.FormatUint(uint64(h.Sum32()), 16)
	nt = append([]byte(path), 0)
	return
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

	case "disk":
		diskSegment()

	case "right":
		rightSegment()

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

	cp, cpNT := cachePathForDir(dir)
	headPath, headMtime := findGitHeadPath(dir)

	var keyBuf [512]byte
	key := keyBuf[:0]
	key = append(key, dir...)
	key = append(key, ':')
	key = strconv.AppendInt(key, headMtime, 10)

	if readCacheToStdout(cpNT, key, wantBranch) {
		return
	}

	sp := abbreviatePath(dir)
	br := branchFromGoGit(dir, headPath)

	writePaneCache(cp, key, sp, br)

	if wantBranch {
		os.Stdout.Write(br)
	} else {
		os.Stdout.Write(sp)
	}
}

// plRight and plLeft are the Powerline solid triangles (U+E0B0, U+E0B2).
// Hardcoded so the Go binary controls separator rendering rather than relying
// on tmux user-option expansion inside #(…) output.
const (
	plRight = ""
	plLeft  = ""
)

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
		os.Stdout.WriteString("#[fg=#6eb4bf,bg=#2f343e]/#[fg=#2f343e,bg=#1f1f1f,nobold]" + plRight)
		return
	}

	cp, cpNT := cachePathForDir(dir)
	headPath, headMtime := findGitHeadPath(dir)

	var keyBuf [512]byte
	key := keyBuf[:0]
	key = append(key, dir...)
	key = append(key, ':')
	key = strconv.AppendInt(key, headMtime, 10)

	if paneSegmentFromCache(cpNT, key) {
		return
	}

	sp := abbreviatePath(dir)
	br := branchFromGoGit(dir, headPath)

	writePaneCache(cp, key, sp, br)
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
					return hp, statMtimeNs(&hst)
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
						return hp, statMtimeNs(&hst)
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
// Returns the bare name with no padding, e.g. "main" or "abc1234".
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
	return []byte(name)
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

// readCacheToStdout reads the per-dir cache file into a stack buffer, checks
// the key, and writes the requested field directly to stdout.
// Returns true on cache hit. Uses openBuf for zero-alloc file open.
func readCacheToStdout(cpNT []byte, key []byte, wantBranch bool) bool {
	fd, errno := openBuf(cpNT, syscall.O_RDONLY)
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

// paneSegmentFromCache reads the per-dir cache file, verifies the key, then
// writes the full coloured segment to stdout. Returns true on cache hit.
func paneSegmentFromCache(cpNT []byte, key []byte) bool {
	fd, errno := openBuf(cpNT, syscall.O_RDONLY)
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
// sp is the abbreviated path; br is the bare branch name (e.g. "main"),
// or nil/empty for non-git directories.
func writeSegment(sp, br []byte) {
	out := make([]byte, 0, 96+len(sp)+len(br))
	// path: cyan on surface1
	out = append(out, "#[fg=#6eb4bf,bg=#2f343e]"...)
	out = append(out, sp...)
	if len(br) > 0 {
		// path→branch sep: fg=surface1(left bg), bg=yellow(right bg)
		out = append(out, "#[fg=#2f343e,bg=#b477cf,nobold]"...)
		out = append(out, plRight...)
		// branch: black text on yellow bg (filled pill)
		out = append(out, "#[fg=#282c33,bg=#b477cf,nobold]"...)
		out = append(out, br...)
		// branch→end sep: fg=yellow(left bg), bg=base(right bg)
		out = append(out, "#[fg=#b477cf,bg=#1f1f1f,nobold]"...)
		out = append(out, plRight...)
	} else {
		// path→end sep: fg=surface1(left bg), bg=base(right bg)
		out = append(out, "#[fg=#2f343e,bg=#1f1f1f,nobold]"...)
		out = append(out, plRight...)
	}
	os.Stdout.Write(out)
}

// writePaneCache writes key, sp, and br to the per-dir cache file atomically via rename.
func writePaneCache(cp string, key, sp, br []byte) {
	_ = os.MkdirAll(cacheDir, 0o755)
	tmp := cp + pidSuffix

	content := make([]byte, 0, len(key)+1+len(sp)+1+len(br)+1)
	content = append(content, key...)
	content = append(content, '\n')
	content = append(content, sp...)
	content = append(content, '\n')
	content = append(content, br...)
	content = append(content, '\n')

	if err := os.WriteFile(tmp, content, 0o644); err == nil {
		os.Rename(tmp, cp) //nolint:errcheck — best-effort atomic write
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
	cacheMtime := statMtimeNs(&cst)
	for _, src := range sources {
		var sst syscall.Stat_t
		if syscall.Stat(src, &sst) == nil {
			if statMtimeNs(&sst) > cacheMtime {
				return false
			}
		}
	}
	return true
}

// ── status-right formatting & metric parsers ─────────────────────────────────

// appendLoadColor appends tmux fg colour matching tmux-cpu's load_status thresholds
// (<30.0%: green, <80.0%: yellow, >=80.0%: red), where tenths is percentage * 10.
func appendLoadColor(dst []byte, tenths int) []byte {
	switch {
	case tenths >= 800:
		return append(dst, "#[fg=red]"...)
	case tenths >= 300:
		return append(dst, "#[fg=yellow]"...)
	default:
		return append(dst, "#[fg=green]"...)
	}
}

// appendTempColor appends tmux fg colour matching tmux-cpu's temp_status thresholds
// (<80C: green, <90C: yellow, >=90C: red).
func appendTempColor(dst []byte, tempC int) []byte {
	switch {
	case tempC >= 90:
		return append(dst, "#[fg=red]"...)
	case tempC >= 80:
		return append(dst, "#[fg=yellow]"...)
	default:
		return append(dst, "#[fg=green]"...)
	}
}

// appendPctTenths formats tenths (e.g. 428 → "42.8%") without fmt allocations.
func appendPctTenths(dst []byte, tenths int) []byte {
	if tenths < 0 {
		tenths = 0
	} else if tenths > 1000 {
		tenths = 1000
	}
	dst = strconv.AppendInt(dst, int64(tenths/10), 10)
	dst = append(dst, '.', byte('0'+tenths%10), '%')
	return dst
}

// appendTempC formats integer Celsius matching "%2.0fC" (e.g. 45 → "45C", 9 → " 9C").
func appendTempC(dst []byte, tempC int) []byte {
	if tempC >= 0 && tempC < 10 {
		dst = append(dst, ' ')
	}
	dst = strconv.AppendInt(dst, int64(tempC), 10)
	return append(dst, 'C')
}

// appendDiskUsage formats "#[fg=<color>]<used>/<total>GB" without fmt allocations.
func appendDiskUsage(dst []byte, usedGB, totalGB uint64) []byte {
	pct := 0
	if totalGB > 0 {
		pct = int((usedGB * 100) / totalGB)
	}
	color := "#a6e3a1"
	if pct >= 90 {
		color = "#f38ba8"
	} else if pct >= 70 {
		color = "#f9e2af"
	}
	dst = append(dst, "#[fg="...)
	dst = append(dst, color...)
	dst = append(dst, ']')
	dst = strconv.AppendUint(dst, usedGB, 10)
	dst = append(dst, '/')
	dst = strconv.AppendUint(dst, totalGB, 10)
	return append(dst, "GB"...)
}

type gpuMetrics struct {
	gpuTenths  int
	tempC      int
	vramTenths int
	hasTemp    bool
	hasVRAM    bool
}

// buildRightStatus assembles the complete status-right string from surface0 through kube(surface1).
func buildRightStatus(
	cpuTenths int,
	cpuTempC int, hasCPUTemp bool,
	ramTenths int,
	gpu gpuMetrics, hasGPU bool,
	usedGB, totalGB uint64, hasDisk bool,
	kube string,
) []byte {
	out := make([]byte, 0, 256+len(kube))

	// CPU on surface0 (#282c33 is already set by status-right entry or set explicitly here)
	out = append(out, "#[fg=#a1c181,bg=#282c33]CPU:"...)
	out = appendLoadColor(out, cpuTenths)
	out = appendPctTenths(out, cpuTenths)

	if hasCPUTemp {
		out = append(out, ' ')
		out = appendTempColor(out, cpuTempC)
		out = appendTempC(out, cpuTempC)
	}

	// RAM
	out = append(out, " #[fg=#73ade9]RAM:"...)
	out = appendLoadColor(out, ramTenths)
	out = appendPctTenths(out, ramTenths)

	// GPU + VRAM
	if hasGPU {
		out = append(out, " #[fg=#b477cf]GPU:"...)
		out = appendLoadColor(out, gpu.gpuTenths)
		out = appendPctTenths(out, gpu.gpuTenths)
		if gpu.hasTemp {
			out = append(out, ' ')
			out = appendTempColor(out, gpu.tempC)
			out = appendTempC(out, gpu.tempC)
		}
		if gpu.hasVRAM {
			out = append(out, " #[fg=#6eb4bf]VRAM:"...)
			out = appendLoadColor(out, gpu.vramTenths)
			out = appendPctTenths(out, gpu.vramTenths)
		}
	}

	// Disk volume (host only)
	if hasDisk {
		out = append(out, " #[fg=#dfc184]VOL:"...)
		out = appendDiskUsage(out, usedGB, totalGB)
	}

	// Separator surface0 (#282c33) → surface1 (#2f343e) + kube segment
	out = append(out, " #[fg=#2f343e,bg=#282c33]"...)
	out = append(out, plLeft...)
	out = append(out, "#[bg=#2f343e]"...)
	if kube != "" {
		out = append(out, kube...)
		out = append(out, ' ')
	}
	return out
}

// parseUintField parses the next whitespace/comma-delimited unsigned integer from b.
func parseUintField(b []byte) (val uint64, rest []byte, ok bool) {
	i := 0
	for i < len(b) && (b[i] == ' ' || b[i] == '\t' || b[i] == ',') {
		i++
	}
	start := i
	for i < len(b) && b[i] >= '0' && b[i] <= '9' {
		val = val*10 + uint64(b[i]-'0')
		i++
	}
	if i == start {
		return 0, b[i:], false
	}
	return val, b[i:], true
}

// parseProcStatCPU parses the aggregate "cpu " line from /proc/stat and returns
// total ticks (user..steal) and idle ticks (idle + iowait).
func parseProcStatCPU(data []byte) (total, idle uint64, ok bool) {
	if len(data) < 5 || data[0] != 'c' || data[1] != 'p' || data[2] != 'u' || data[3] != ' ' {
		return 0, 0, false
	}
	line := data[4:]
	if nl := bytes.IndexByte(line, '\n'); nl >= 0 {
		line = line[:nl]
	}
	var fields [8]uint64
	n := 0
	for n < len(fields) {
		v, rest, valid := parseUintField(line)
		if !valid {
			break
		}
		fields[n] = v
		n++
		line = rest
	}
	if n < 4 {
		return 0, 0, false
	}
	for i := 0; i < n; i++ {
		total += fields[i]
	}
	idle = fields[3] + fields[4]
	return total, idle, true
}

// calcCPUTenths computes CPU busy percentage * 10 from two /proc/stat snapshots.
func calcCPUTenths(prevTotal, prevIdle, curTotal, curIdle uint64) (int, bool) {
	if curTotal <= prevTotal {
		return 0, false
	}
	dTotal := curTotal - prevTotal
	var dIdle uint64
	if curIdle >= prevIdle {
		dIdle = curIdle - prevIdle
	}
	if dIdle > dTotal {
		dIdle = dTotal
	}
	busy := dTotal - dIdle
	tenths := int((busy*1000 + dTotal/2) / dTotal)
	if tenths > 1000 {
		tenths = 1000
	}
	return tenths, true
}

// parseMeminfoTenths parses /proc/meminfo and returns RAM usage percentage * 10.
func parseMeminfoTenths(data []byte) (int, bool) {
	var memTotal, memAvail, memFree, buffers, cached uint64
	var hasTotal, hasAvail bool

	for len(data) > 0 {
		var line []byte
		if nl := bytes.IndexByte(data, '\n'); nl >= 0 {
			line = data[:nl]
			data = data[nl+1:]
		} else {
			line = data
			data = nil
		}
		switch {
		case bytes.HasPrefix(line, []byte("MemTotal:")):
			if v, _, ok := parseUintField(line[len("MemTotal:"):]); ok {
				memTotal = v
				hasTotal = true
			}
		case bytes.HasPrefix(line, []byte("MemAvailable:")):
			if v, _, ok := parseUintField(line[len("MemAvailable:"):]); ok {
				memAvail = v
				hasAvail = true
			}
		case bytes.HasPrefix(line, []byte("MemFree:")):
			memFree, _, _ = parseUintField(line[len("MemFree:"):])
		case bytes.HasPrefix(line, []byte("Buffers:")):
			buffers, _, _ = parseUintField(line[len("Buffers:"):])
		case bytes.HasPrefix(line, []byte("Cached:")):
			cached, _, _ = parseUintField(line[len("Cached:"):])
		}
		if hasTotal && hasAvail {
			break
		}
	}
	if !hasTotal || memTotal == 0 {
		return 0, false
	}
	avail := memAvail
	if !hasAvail {
		avail = memFree + buffers + cached
	}
	if avail > memTotal {
		avail = memTotal
	}
	used := memTotal - avail
	return int((used*1000 + memTotal/2) / memTotal), true
}

// parseNvidiaCSV parses `nvidia-smi --query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total --format=csv,noheader,nounits`.
func parseNvidiaCSV(data []byte) (gpuMetrics, bool) {
	var sumUtil, sumTemp, sumUsed, sumTotal uint64
	var count uint64

	for len(data) > 0 {
		var line []byte
		if nl := bytes.IndexByte(data, '\n'); nl >= 0 {
			line = data[:nl]
			data = data[nl+1:]
		} else {
			line = data
			data = nil
		}
		line = bytes.TrimSpace(line)
		if len(line) == 0 {
			continue
		}
		u, r1, ok1 := parseUintField(line)
		t, r2, ok2 := parseUintField(r1)
		mUsed, r3, ok3 := parseUintField(r2)
		mTot, _, ok4 := parseUintField(r3)
		if !ok1 || !ok2 || !ok3 || !ok4 {
			continue
		}
		sumUtil += u
		sumTemp += t
		sumUsed += mUsed
		sumTotal += mTot
		count++
	}
	if count == 0 {
		return gpuMetrics{}, false
	}
	gpuTenths := int((sumUtil*10 + count/2) / count)
	tempC := int((sumTemp + count/2) / count)
	vramTenths := 0
	if sumTotal > 0 {
		vramTenths = int((sumUsed*1000 + sumTotal/2) / sumTotal)
	}
	return gpuMetrics{
		gpuTenths:  gpuTenths,
		tempC:      tempC,
		vramTenths: vramTenths,
		hasTemp:    true,
		hasVRAM:    sumTotal > 0,
	}, true
}
