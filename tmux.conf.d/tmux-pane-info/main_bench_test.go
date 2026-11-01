package main

import (
	"io"
	"os"
	"strconv"
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
	b.ReportAllocs()
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_ = abbreviatePath(dir)
	}
}

func BenchmarkReadCacheToStdout(b *testing.B) {
	dir := "/home/kpango/go/src/github.com/kpango/dotfiles"
	silenceStdout(b)
	paneOut(dir, false) // prime cache

	_, cpNT := cachePathForDir(dir)
	_, headMtime := findGitHeadPath(dir)
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
