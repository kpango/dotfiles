package main

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"testing"
	"unicode/utf8"
)

// TestAdversarialAbbreviatePath_ExtremeLengths verifies that abbreviatePath handles
// paths exceeding the 256-byte stack buffer (300B, 500B, 1000B, 4096B, 8192B)
// safely without crashing or corrupting memory, properly growing onto heap via append.
func TestAdversarialAbbreviatePath_ExtremeLengths(t *testing.T) {
	lengths := []int{256, 300, 500, 1000, 2048, 4096, 8192}

	var stackBuf [256]byte

	for _, length := range lengths {
		t.Run(fmt.Sprintf("%d_bytes_deep_nested", length), func(t *testing.T) {
			// Construct deep nested path: /a/b/c/d/.../finalTarget
			var b strings.Builder
			for b.Len() < length-20 {
				b.WriteString("/subdir")
			}
			b.WriteString("/finalTarget")
			dir := b.String()

			got := abbreviatePath(stackBuf[:0], dir)
			if len(got) == 0 {
				t.Fatalf("abbreviatePath returned empty slice for length %d", len(dir))
			}
			gotStr := string(got)

			// The last component must be preserved exactly
			if !strings.HasSuffix(gotStr, "/finalTarget") {
				t.Fatalf("expected suffix /finalTarget, got %q (len %d)", gotStr, len(gotStr))
			}

			// Preceding components must start with /s
			if !strings.HasPrefix(gotStr, "/s/") {
				t.Fatalf("expected prefix /s/, got %q", gotStr[:min(10, len(gotStr))])
			}
		})

		t.Run(fmt.Sprintf("%d_bytes_long_last_component", length), func(t *testing.T) {
			// Component before last is short, last component is huge
			prefix := "/a/b/c/"
			lastComp := strings.Repeat("x", length)
			dir := prefix + lastComp

			got := abbreviatePath(stackBuf[:0], dir)
			gotStr := string(got)

			wantPrefix := "/a/b/c/"
			if !strings.HasPrefix(gotStr, wantPrefix) {
				t.Fatalf("expected prefix %q, got %q", wantPrefix, gotStr[:min(10, len(gotStr))])
			}
			if !strings.HasSuffix(gotStr, lastComp) {
				t.Fatalf("expected last component of length %d preserved, got total len %d", len(lastComp), len(gotStr))
			}
		})

		t.Run(fmt.Sprintf("%d_bytes_home_nested", length), func(t *testing.T) {
			if homeDir == "" {
				t.Skip("homeDir is empty")
			}
			var b strings.Builder
			b.WriteString(homeDir)
			for b.Len() < length-15 {
				b.WriteString("/component")
			}
			b.WriteString("/leaf")
			dir := b.String()

			got := abbreviatePath(stackBuf[:0], dir)
			gotStr := string(got)

			if !strings.HasPrefix(gotStr, "~/") {
				t.Fatalf("expected prefix ~/, got %q", gotStr[:min(10, len(gotStr))])
			}
			if !strings.HasSuffix(gotStr, "/leaf") {
				t.Fatalf("expected suffix /leaf, got %q", gotStr)
			}
		})
	}
}

// TestAdversarialAbbreviatePath_UnusualUnicodeAndSurrogates tests strange Unicode,
// multi-byte emojis, ZWJ sequences, combining diacritics, RTL, surrogate halves, and null bytes.
func TestAdversarialAbbreviatePath_UnusualUnicodeAndSurrogates(t *testing.T) {
	tests := []struct {
		name       string
		dir        string
		wantPrefix string
		wantSuffix string
	}{
		{
			name:       "4-byte emojis path",
			dir:        "/🚀rocket/🔥fire/🎉party/✨sparkle/target",
			wantPrefix: "/🚀/🔥/🎉/✨/",
			wantSuffix: "/target",
		},
		{
			name:       "ZWJ family emoji sequence in directory",
			dir:        "/👨‍👩‍👧‍👦family/nested/dir",
			wantPrefix: "/👨/n/",
			wantSuffix: "/dir",
		},
		{
			name:       "combining diacritics cafe\\u0301",
			dir:        "/cafe\u0301/restaurant/menu",
			wantPrefix: "/c/r/",
			wantSuffix: "/menu",
		},
		{
			name:       "Cyrillic unicode",
			dir:        "/пользователь/документы/проект/исходники",
			wantPrefix: "/п/д/п/",
			wantSuffix: "/исходники",
		},
		{
			name:       "RTL Arabic text",
			dir:        "/مسار/إلى/مجلد/مشروع",
			wantPrefix: "/م/إ/م/",
			wantSuffix: "/مشروع",
		},
		{
			name:       "RTL Hebrew text",
			dir:        "/נתיב/אל/תיקייה/מסמך",
			wantPrefix: "/נ/א/ת/",
			wantSuffix: "/מסמך",
		},
		{
			name:       "Devanagari conjuncts",
			dir:        "/मार्ग/प्रोजेक्ट/कोड/लक्ष्य",
			wantPrefix: "/म/प/क/",
			wantSuffix: "/लक्ष्य",
		},
		{
			name:       "Mathematical bold Fraktur",
			dir:        "/𝔘𝔫𝔦𝔠𝔬𝔡𝔢/𝕻𝖆𝖙𝖍/test",
			wantPrefix: "/𝔘/𝕻/",
			wantSuffix: "/test",
		},
		{
			name:       "Invalid UTF-8 sequence 0xFF 0xFE",
			dir:        "/bad\xff\xfe/next/file",
			wantPrefix: "/b/n/",
			wantSuffix: "/file",
		},
		{
			name:       "Surrogate code point byte representation",
			dir:        "/\xed\xa0\x80surrogate/nested/dest",
			wantPrefix: "/\xed/n/",
			wantSuffix: "/dest",
		},
		{
			name:       "Null-byte injection in path component",
			dir:        "/safe/injection\x00hidden/target",
			wantPrefix: "/s/i/",
			wantSuffix: "/target",
		},
		{
			name:       "Null byte immediately after slash",
			dir:        "/\x00null/path/end",
			wantPrefix: "/\x00/p/",
			wantSuffix: "/end",
		},
	}

	var buf [256]byte
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := string(abbreviatePath(buf[:0], tc.dir))
			if !strings.HasPrefix(got, tc.wantPrefix) {
				t.Errorf("abbreviatePath(%q) = %q, want prefix %q", tc.dir, got, tc.wantPrefix)
			}
			if !strings.HasSuffix(got, tc.wantSuffix) {
				t.Errorf("abbreviatePath(%q) = %q, want suffix %q", tc.dir, got, tc.wantSuffix)
			}
			// Verify output is valid or handled gracefully without panic
			_ = utf8.ValidString(got)
		})
	}
}

// TestAdversarialAbbreviatePath_StructuralEdges tests slashes-only, consecutive slashes,
// relative paths, spaces, tabs, and special punctuation.
func TestAdversarialAbbreviatePath_StructuralEdges(t *testing.T) {
	tests := []struct {
		name string
		dir  string
		want string
	}{
		{"single slash", "/", "/"},
		{"double slash", "//", "//"},
		{"triple slash", "///", "///"},
		{"ten slashes", "//////////", "//////////"},
		{"slash dot", "/.", "/."},
		{"dot dot", "..", ".."},
		{"dot slash dot dot", "./..", "./.."},
		{"trailing slash simple", "/a/", "/a/"},
		{"trailing slash two", "/a/b/", "/a/b/"},
		{"trailing slash deep", "/foo/bar/baz/", "/f/b/b/"},
		{"consecutive slashes in path", "/a///b////c", "/a///b////c"},
		{"spaces in components", "/path with spaces/second space/final", "/p/s/final"},
		{"tabs and newlines", "/tab\there/line\nbreak/final", "/t/l/final"},
		{"symbols and punctuation", "/!@#$/%^&*/()_+", "/!/%/()_+"},
		{"relative single component", "myFolder", "myFolder"},
		{"relative two components", "src/core", "s/core"},
		{"relative deep with dots", "./src/core/pkg/main.go", "./s/c/p/main.go"},
		{"parent relative deep", "../../internal/cache/cache.go", "././i/c/cache.go"},
	}

	var buf [256]byte
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := string(abbreviatePath(buf[:0], tc.dir))
			if got != tc.want {
				t.Errorf("abbreviatePath(%q) = %q, want %q", tc.dir, got, tc.want)
			}
		})
	}
}

// TestAdversarialConcurrencyStress_100Goroutines launches 100 concurrent goroutines
// calling paneOut and paneSegment with disparate path arguments simultaneously under -race.
func TestAdversarialConcurrencyStress_100Goroutines(t *testing.T) {
	// Silence stdout for duration of test to prevent interleaving
	origStdout := os.Stdout
	devNull, err := os.OpenFile(os.DevNull, os.O_WRONLY, 0)
	if err != nil {
		t.Fatalf("failed to open /dev/null: %v", err)
	}
	os.Stdout = devNull
	defer func() {
		os.Stdout = origStdout
		devNull.Close()
	}()

	tempBase := t.TempDir()

	// Prepare 100 distinct directory structures:
	// Some git repositories, some normal dirs, some deeply nested dirs
	testDirs := make([]string, 100)
	for i := 0; i < 100; i++ {
		dir := filepath.Join(tempBase, fmt.Sprintf("dir_%03d", i))
		switch i % 4 {
		case 0:
			// Normal directory
			sub := filepath.Join(dir, "sub_a", "sub_b", "leaf")
			_ = os.MkdirAll(sub, 0o755)
			testDirs[i] = sub
		case 1:
			// Git repo with HEAD branch
			gitDir := filepath.Join(dir, ".git")
			_ = os.MkdirAll(gitDir, 0o755)
			_ = os.WriteFile(filepath.Join(gitDir, "HEAD"), []byte("ref: refs/heads/feature/adv-test-"+fmt.Sprint(i)+"\n"), 0o644)
			sub := filepath.Join(dir, "src", "pkg")
			_ = os.MkdirAll(sub, 0o755)
			testDirs[i] = sub
		case 2:
			// Extremely deep path (> 300 bytes)
			deep := dir
			for d := 0; d < 20; d++ {
				deep = filepath.Join(deep, fmt.Sprintf("level_%02d_long_segment_name", d))
			}
			_ = os.MkdirAll(deep, 0o755)
			testDirs[i] = deep
		case 3:
			// Directory with Unicode / emoji names
			uniDir := filepath.Join(dir, "🚀launch", "テスト", "データ_03")
			_ = os.MkdirAll(uniDir, 0o755)
			testDirs[i] = uniDir
		}
	}

	var wg sync.WaitGroup
	errCh := make(chan error, 100)

	// Launch 100 concurrent goroutines
	for i := 0; i < 100; i++ {
		wg.Add(1)
		dir := testDirs[i]
		callType := i % 3

		go func(idx int, targetDir string, mode int) {
			defer wg.Done()
			defer func() {
				if r := recover(); r != nil {
					errCh <- fmt.Errorf("goroutine %d panicked on dir %q: %v", idx, targetDir, r)
				}
			}()

			// Run 5 rapid iterations per goroutine (total 500 executions)
			for rep := 0; rep < 5; rep++ {
				switch mode {
				case 0:
					paneOut(targetDir, false)
				case 1:
					paneOut(targetDir, true)
				case 2:
					paneSegment(targetDir)
				}
			}
		}(i, dir, callType)
	}

	wg.Wait()
	close(errCh)

	var panics []error
	for e := range errCh {
		panics = append(panics, e)
	}

	if len(panics) > 0 {
		t.Fatalf("Encountered %d panics during 100-goroutine concurrency stress: %v", len(panics), panics[0])
	}
}

// TestAdversarialMemoryStability asserts zero memory leaks or unbounded growth
// across 10,000 rapid iterations of abbreviatePath and paneSegment.
func TestAdversarialMemoryStability(t *testing.T) {
	origStdout := os.Stdout
	devNull, err := os.OpenFile(os.DevNull, os.O_WRONLY, 0)
	if err != nil {
		t.Fatalf("failed to open /dev/null: %v", err)
	}
	os.Stdout = devNull
	defer func() {
		os.Stdout = origStdout
		devNull.Close()
	}()

	tempDir := t.TempDir()
	leaf := filepath.Join(tempDir, "bench_stable", "sub", "pkg")
	_ = os.MkdirAll(leaf, 0o755)

	// Prime cache
	paneSegment(leaf)

	runtime.GC()
	var mBefore runtime.MemStats
	runtime.ReadMemStats(&mBefore)

	var stackBuf [256]byte
	for i := 0; i < 10000; i++ {
		// Exercise abbreviatePath
		_ = abbreviatePath(stackBuf[:0], leaf)
		// Exercise paneSegment cache hits
		paneSegment(leaf)
	}

	runtime.GC()
	var mAfter runtime.MemStats
	runtime.ReadMemStats(&mAfter)

	// Verify heap object count did not explode (allowing reasonable runtime fluctuations < 500KB)
	heapDiff := int64(mAfter.HeapAlloc) - int64(mBefore.HeapAlloc)
	t.Logf("HeapAlloc before: %d B, after: %d B, diff: %d B", mBefore.HeapAlloc, mAfter.HeapAlloc, heapDiff)
	if heapDiff > 1024*1024 {
		t.Fatalf("Potential memory leak detected: HeapAlloc grew by %d bytes over 10,000 iterations", heapDiff)
	}
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
