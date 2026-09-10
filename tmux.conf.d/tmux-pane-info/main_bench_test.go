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
