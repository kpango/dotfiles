package main

import (
	"io"
	"os"
	"strconv"
	"strings"
	"testing"
)

func silenceStdout(b *testing.B) {
	b.Helper()
	orig := os.Stdout
	os.Stdout, _ = os.OpenFile(os.DevNull, os.O_WRONLY, 0)
	b.Cleanup(func() {
		os.Stdout.Close()
		os.Stdout = orig
	})
}

func BenchmarkReadCacheHit(b *testing.B) {
	dir := "/home/kpango/go/src/github.com/kpango/dotfiles"
	silenceStdout(b)
	paneOut(dir, false) // prime cache
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		paneOut(dir, false)
	}
}

func BenchmarkReadCacheHitBranch(b *testing.B) {
	dir := "/home/kpango/go/src/github.com/kpango/dotfiles"
	silenceStdout(b)
	paneOut(dir, true)
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		paneOut(dir, true)
	}
}

func BenchmarkFindGitHeadPath(b *testing.B) {
	dir := "/home/kpango/go/src/github.com/kpango/dotfiles"
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, _ = findGitHeadPath(dir)
	}
}

func BenchmarkAbbreviatePath(b *testing.B) {
	dir := "/home/kpango/go/src/github.com/kpango/dotfiles"
	var buf [256]byte
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_ = abbreviatePath(buf[:0], dir)
	}
}

func TestAbbreviatePath(t *testing.T) {
	tests := []struct {
		name string
		dir  string
		want string
	}{
		{"exact home", homeDir, "~"},
		{"home trailing slash", homeDir + "/", "~/"},
		{"home single subfolder", homeDir + "/dotfiles", "~/dotfiles"},
		{"home nested path", homeDir + "/go/src/github.com/kpango/dotfiles", "~/g/s/g/k/dotfiles"},
		{"home deep nested", homeDir + "/foo/bar/baz/qux", "~/f/b/b/qux"},
		{"home trailing slash nested", homeDir + "/foo/bar/", "~/f/b/"},
		{"home consecutive slashes", homeDir + "//foo", "~//foo"},
		{"home prefix in other name", "/home/kpango-other/dir", "/h/k/dir"},
		{"root dir", "/", "/"},
		{"empty string", "", ""},
		{"single root subfolder", "/var", "/var"},
		{"two root subfolders", "/var/log", "/v/log"},
		{"syslog path", "/var/log/syslog", "/v/l/syslog"},
		{"nginx log path", "/var/log/nginx/access.log", "/v/l/n/access.log"},
		{"deep non-home path", "/a/b/c/d/e", "/a/b/c/d/e"},
		{"trailing slash non-home", "/a/b/c/", "/a/b/c/"},
		{"relative single", "relative", "relative"},
		{"relative two", "relative/path", "r/path"},
		{"relative three", "relative/path/to/target", "r/p/t/target"},
		{"multibyte unicode", homeDir + "/ドキュメント/開発/dotfiles", "~/ド/開/dotfiles"},
		{"emoji unicode", "/tmp/🚀project/src", "/t/🚀/src"},
	}

	var buf [256]byte
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := string(abbreviatePath(buf[:0], tc.dir))
			if got != tc.want {
				t.Fatalf("abbreviatePath(%q) = %q, want %q", tc.dir, got, tc.want)
			}
		})
	}
}

func BenchmarkReadCacheToStdout(b *testing.B) {
	dir := "/home/kpango/go/src/github.com/kpango/dotfiles"
	silenceStdout(b)
	paneOut(dir, false) // prime cache

	var cpBuf [128]byte
	cpNT := appendCachePathNT(cpBuf[:0], dir)
	headMtime := findGitHeadMtime(dir)
	var keyBuf [512]byte
	key := keyBuf[:0]
	key = append(key, dir...)
	key = append(key, ':')
	key = strconv.AppendInt(key, headMtime, 10)

	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		readCacheToStdout(cpNT, key, false)
	}
}

func BenchmarkPaneSegmentCacheHit(b *testing.B) {
	dir := "/home/kpango/go/src/github.com/kpango/dotfiles"
	silenceStdout(b)
	paneSegment(dir) // prime cache
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		paneSegment(dir)
	}
}

func BenchmarkWriteSegment(b *testing.B) {
	sp := []byte("~/g/s/g/k/dotfiles")
	br := []byte(" main")
	silenceStdout(b)
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		writeSegment(sp, br)
	}
}

// Ensure io is used (suppress LSP warning).
var _ io.Writer = io.Discard

func TestParseProcStatAndCalcCPU(t *testing.T) {
	tests := []struct {
		name       string
		snap1      string
		snap2      string
		wantTenths int
		wantOK     bool
	}{
		{
			name:       "25 percent busy",
			snap1:      "cpu  1000 0 500 8500 0 0 0 0 0 0\ncpu0 500 0 250 4250\n",
			snap2:      "cpu  1200 0 550 9250 0 0 0 0 0 0\ncpu0 600 0 275 4625\n",
			wantTenths: 250,
			wantOK:     true,
		},
		{
			name:       "idle plus iowait counted as idle",
			snap1:      "cpu  100 0 100 700 100 0 0 0\n",
			snap2:      "cpu  110 0 100 780 110 0 0 0\n",
			wantTenths: 100,
			wantOK:     true,
		},
		{
			name:       "counter reset rejected",
			snap1:      "cpu  5000 0 500 8500 0 0 0 0\n",
			snap2:      "cpu  1000 0 500 8500 0 0 0 0\n",
			wantTenths: 0,
			wantOK:     false,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			t1, i1, ok1 := parseProcStatCPU([]byte(tc.snap1))
			t2, i2, ok2 := parseProcStatCPU([]byte(tc.snap2))
			if !ok1 || !ok2 {
				t.Fatalf("parseProcStatCPU failed: ok1=%v ok2=%v", ok1, ok2)
			}
			got, ok := calcCPUTenths(t1, i1, t2, i2)
			if ok != tc.wantOK || got != tc.wantTenths {
				t.Fatalf("calcCPUTenths() = (%d, %v), want (%d, %v)", got, ok, tc.wantTenths, tc.wantOK)
			}
		})
	}
}

func TestParseMeminfoTenths(t *testing.T) {
	tests := []struct {
		name       string
		input      string
		wantTenths int
		wantOK     bool
	}{
		{
			name: "modern MemAvailable",
			input: "MemTotal:       32000000 kB\n" +
				"MemFree:         4000000 kB\n" +
				"MemAvailable:   20000000 kB\n" +
				"Buffers:         1000000 kB\n",
			wantTenths: 375,
			wantOK:     true,
		},
		{
			name: "legacy fallback without MemAvailable",
			input: "MemTotal:       10000000 kB\n" +
				"MemFree:         2000000 kB\n" +
				"Buffers:         1000000 kB\n" +
				"Cached:          3000000 kB\n",
			wantTenths: 400,
			wantOK:     true,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got, ok := parseMeminfoTenths([]byte(tc.input))
			if ok != tc.wantOK || got != tc.wantTenths {
				t.Fatalf("parseMeminfoTenths() = (%d, %v), want (%d, %v)", got, ok, tc.wantTenths, tc.wantOK)
			}
		})
	}
}

func TestParseNvidiaCSV(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		wantGPU  int
		wantTemp int
		wantVRAM int
		wantOK   bool
	}{
		{
			name:     "single GPU",
			input:    "6, 45, 3510, 8192\n",
			wantGPU:  60,
			wantTemp: 45,
			wantVRAM: 428,
			wantOK:   true,
		},
		{
			name:     "dual GPU averaged util/temp and summed VRAM",
			input:    "10, 50, 2000, 8000\n30, 60, 6000, 8000\n",
			wantGPU:  200,
			wantTemp: 55,
			wantVRAM: 500,
			wantOK:   true,
		},
		{
			name:   "empty output",
			input:  "\n",
			wantOK: false,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got, ok := parseNvidiaCSV([]byte(tc.input))
			if ok != tc.wantOK {
				t.Fatalf("ok = %v, want %v", ok, tc.wantOK)
			}
			if !ok {
				return
			}
			if got.gpuTenths != tc.wantGPU || got.tempC != tc.wantTemp || got.vramTenths != tc.wantVRAM {
				t.Fatalf("got %+v, want gpu=%d temp=%d vram=%d", got, tc.wantGPU, tc.wantTemp, tc.wantVRAM)
			}
		})
	}
}

func TestColorAndFormatHelpers(t *testing.T) {
	if got := string(appendLoadColor(nil, 299)); got != "#[fg=green]" {
		t.Fatalf("29.9%% color = %q", got)
	}
	if got := string(appendLoadColor(nil, 300)); got != "#[fg=yellow]" {
		t.Fatalf("30.0%% color = %q", got)
	}
	if got := string(appendLoadColor(nil, 800)); got != "#[fg=red]" {
		t.Fatalf("80.0%% color = %q", got)
	}
	if got := string(appendTempColor(nil, 79)); got != "#[fg=green]" {
		t.Fatalf("79C color = %q", got)
	}
	if got := string(appendTempColor(nil, 80)); got != "#[fg=yellow]" {
		t.Fatalf("80C color = %q", got)
	}
	if got := string(appendTempColor(nil, 90)); got != "#[fg=red]" {
		t.Fatalf("90C color = %q", got)
	}
	if got := string(appendPctTenths(nil, 60)); got != "6.0%" {
		t.Fatalf("appendPctTenths(60) = %q", got)
	}
	if got := string(appendTempC(nil, 9)); got != " 9C" {
		t.Fatalf("appendTempC(9) = %q", got)
	}
	if got := string(appendDiskUsage(nil, 75, 100)); got != "#[fg=#f9e2af]75/100GB" {
		t.Fatalf("appendDiskUsage(75,100) = %q", got)
	}
}

func BenchmarkDiskSegment(b *testing.B) {
	silenceStdout(b)
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		diskSegment()
	}
}

func BenchmarkRightSegmentCacheHit(b *testing.B) {
	silenceStdout(b)
	rightSegment() // prime caches
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		rightSegment()
	}
}

func BenchmarkLinuxCPUTempC(b *testing.B) {
	if _, ok := linuxCPUTempC(); !ok {
		b.Skip("no CPU temperature sensor available")
	}
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, _ = linuxCPUTempC()
	}
}

func BenchmarkReadHwmonTemps(b *testing.B) {
	if cachedHwmonH < 0 || len(cachedHwmonIndices) == 0 {
		_, _ = linuxCPUTempC() // prime cache
		if cachedHwmonH < 0 || len(cachedHwmonIndices) == 0 {
			b.Skip("no hwmon indices available")
		}
	}
	var buf [64]byte
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, _ = readHwmonTemps(cachedHwmonH, cachedHwmonIndices, buf[:])
	}
}

func TestBranchFromHead(t *testing.T) {
	tmpDir := t.TempDir()

	tests := []struct {
		name     string
		content  string
		want     string
		fileMiss bool
	}{
		{
			name:    "standard branch",
			content: "ref: refs/heads/main\n",
			want:    "main",
		},
		{
			name:    "nested feature branch",
			content: "ref: refs/heads/feature/perf-opt\n",
			want:    "feature/perf-opt",
		},
		{
			name:    "detached HEAD commit hash",
			content: "4a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b\n",
			want:    "4a1b2c3",
		},
		{
			name:    "short detached HEAD hash",
			content: "abc12\n",
			want:    "abc12",
		},
		{
			name:    "tag reference",
			content: "ref: refs/tags/v1.0.0\n",
			want:    "v1.0.0",
		},
		{
			name:    "empty file",
			content: "",
			want:    "",
		},
		{
			name:     "non-existent file",
			fileMiss: true,
			want:     "",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			path := tmpDir + "/" + tc.name
			if !tc.fileMiss {
				if err := os.WriteFile(path, []byte(tc.content), 0644); err != nil {
					t.Fatal(err)
				}
			}
			got := string(branchFromHead(path))
			if got != tc.want {
				t.Fatalf("branchFromHead(%q) = %q, want %q", tc.name, got, tc.want)
			}
		})
	}
}

func TestParseKubeConfig(t *testing.T) {
	testYAML := `
apiVersion: v1
clusters:
- cluster:
    server: https://127.0.0.1:6443
  name: test-cluster
contexts:
- context:
    cluster: other-cluster
    namespace: other-ns
  name: other-ctx
- context:
    cluster: test-cluster
    namespace: "my-namespace" # inline comment
  name: 'my-ctx'
- context:
    cluster: default-cluster
  name: default-ctx
current-context: my-ctx # active context
users:
- name: my-ctx
  user:
    token: secret
`
	data := []byte(testYAML)
	ctx := parseKubeCurrentContext(data)
	if ctx != "my-ctx" {
		t.Fatalf("parseKubeCurrentContext = %q, want 'my-ctx'", ctx)
	}

	ns, ok := parseKubeContextNamespace(data, ctx)
	if !ok || ns != "my-namespace" {
		t.Fatalf("parseKubeContextNamespace = (%q, %v), want ('my-namespace', true)", ns, ok)
	}

	// Test default namespace fallback when omitted
	nsDefault, okDefault := parseKubeContextNamespace(data, "default-ctx")
	if !okDefault || nsDefault != "default" {
		t.Fatalf("default fallback = (%q, %v), want ('default', true)", nsDefault, okDefault)
	}

	// Test non-existent context
	if _, okMissing := parseKubeContextNamespace(data, "nonexistent"); okMissing {
		t.Fatalf("parseKubeContextNamespace for nonexistent should return false")
	}
}

func TestCleanYAMLValue(t *testing.T) {
	cases := []struct {
		input string
		want  string
	}{
		{`"my-value"`, `my-value`},
		{`'my-value'`, `my-value`},
		{`"my-value" # comment`, `my-value`},
		{`my-value # comment`, `my-value`},
		{`  simple  `, `simple`},
	}
	for _, tc := range cases {
		if got := cleanYAMLValue([]byte(tc.input)); got != tc.want {
			t.Fatalf("cleanYAMLValue(%q) = %q, want %q", tc.input, got, tc.want)
		}
	}
}

func TestCachePathForDir(t *testing.T) {
	tests := []struct {
		dir      string
		wantHash string
	}{
		{"", "811c9dc5"},
		{"/", "2a0c975e"},
		{"/home/kpango/go/src/github.com/kpango/dotfiles", "9edb8909"},
	}
	for _, tc := range tests {
		path, nt := cachePathForDir(tc.dir)
		wantPath := cacheFilePath + "." + tc.wantHash
		if path != wantPath {
			t.Errorf("cachePathForDir(%q) path = %q, want %q", tc.dir, path, wantPath)
		}
		if len(nt) != len(path)+1 || nt[len(nt)-1] != 0 || string(nt[:len(nt)-1]) != path {
			t.Errorf("cachePathForDir(%q) nt null termination invalid", tc.dir)
		}
	}
}

func TestBuildRightStatus(t *testing.T) {
	gpu := gpuMetrics{
		gpuTenths:  150,
		tempC:      55,
		vramTenths: 420,
		hasTemp:    true,
		hasVRAM:    true,
	}

	// Test 1: Stack buffer vs nil buffer produce identical output
	var buf [512]byte
	outStack := string(buildRightStatus(buf[:0], 250, 48, true, 450, gpu, true, 50, 100, true, "my-kube"))
	outNil := string(buildRightStatus(nil, 250, 48, true, 450, gpu, true, 50, 100, true, "my-kube"))
	if outStack != outNil {
		t.Fatalf("buildRightStatus stack buffer output does not match nil buffer output:\nstack: %q\nnil:   %q", outStack, outNil)
	}

	// Test 2: Invariants in output string
	if len(outStack) == 0 {
		t.Fatal("buildRightStatus returned empty output")
	}
	for _, expected := range []string{"CPU:", "25.0%", "48C", "RAM:", "45.0%", "GPU:", "15.0%", "55C", "VRAM:", "42.0%", "VOL:", "50/100GB", "my-kube"} {
		if !strings.Contains(outStack, expected) {
			t.Errorf("expected buildRightStatus output to contain %q, got: %s", expected, outStack)
		}
	}

	// Test 3: Minimal without optional metrics
	outMin := string(buildRightStatus(buf[:0], 50, 0, false, 200, gpuMetrics{}, false, 0, 0, false, ""))
	for _, omitted := range []string{"GPU:", "VRAM:", "VOL:", "⎈"} {
		if strings.Contains(outMin, omitted) {
			t.Errorf("minimal output should not contain %q", omitted)
		}
	}
}
