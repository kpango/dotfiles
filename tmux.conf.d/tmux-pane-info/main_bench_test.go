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
