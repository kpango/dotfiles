//go:build darwin

package main

import (
	"bytes"
	"context"
	"os"
	"os/exec"
	"runtime"
	"strconv"
	"syscall"
	"time"
)

// statMtimeNs returns st's mtime in nanoseconds. Darwin's syscall.Stat_t
// exposes this as the Mtimespec field (Linux uses Mtim instead — see
// stat_linux.go). Field name is the only difference; Timespec.Sec/Nsec are
// int64 on both platforms.
func statMtimeNs(st *syscall.Stat_t) int64 {
	return st.Mtimespec.Sec*1e9 + st.Mtimespec.Nsec
}

func diskUsageGB() (used, total uint64, ok bool) {
	var stat syscall.Statfs_t
	if err := syscall.Statfs("/", &stat); err != nil {
		return 0, 0, false
	}
	bsize := uint64(stat.Bsize)
	total = (stat.Blocks * bsize) / (1024 * 1024 * 1024)
	free := (stat.Bfree * bsize) / (1024 * 1024 * 1024)
	return total - free, total, true
}

func diskSegment() {
	used, total, ok := diskUsageGB()
	if !ok {
		return
	}
	var buf [64]byte
	os.Stdout.Write(appendDiskUsage(buf[:0], used, total))
}

func rightSegment() {
	cpuTenths, ramTenths := darwinSysMetrics()
	kube := kubeSegment("green", "brightcyan")
	os.Stdout.Write(buildRightStatus(
		cpuTenths,
		0, false,
		ramTenths,
		gpuMetrics{}, false,
		0, 0, false,
		kube,
	))
}

func darwinSysMetrics() (cpuTenths, ramTenths int) {
	cp := cacheDir + "/tmux-sys-darwin"
	now := time.Now().UnixNano()
	if cdata, err := os.ReadFile(cp); err == nil {
		ts, r1, ok1 := parseUintField(cdata)
		c, r2, ok2 := parseUintField(r1)
		m, _, ok3 := parseUintField(r2)
		if ok1 && ok2 && ok3 && now-int64(ts) >= 0 && now-int64(ts) < int64(3*time.Second) {
			return int(c), int(m)
		}
	}

	ctx, cancel := context.WithTimeout(context.Background(), 1500*time.Millisecond)
	defer cancel()

	if out, err := exec.CommandContext(ctx, "ps", "-A", "-o", "%cpu").Output(); err == nil {
		var sumTenths int64
		for _, line := range bytes.Split(out, []byte{'\n'}) {
			line = bytes.TrimSpace(line)
			if len(line) == 0 || line[0] == '%' {
				continue
			}
			if f, ferr := strconv.ParseFloat(string(line), 64); ferr == nil {
				sumTenths += int64(f*10 + 0.5)
			}
		}
		ncpu := int64(runtime.NumCPU())
		if ncpu < 1 {
			ncpu = 1
		}
		cpuTenths = int((sumTenths + ncpu/2) / ncpu)
		if cpuTenths > 1000 {
			cpuTenths = 1000
		}
	}

	if out, err := exec.CommandContext(ctx, "vm_stat").Output(); err == nil {
		var usedCached, cached, free uint64
		for _, line := range bytes.Split(out, []byte{'\n'}) {
			idx := bytes.IndexByte(line, ':')
			if idx < 0 {
				continue
			}
			key := line[:idx]
			val, _, ok := parseUintField(line[idx+1:])
			if !ok {
				continue
			}
			switch {
			case bytes.Equal(key, []byte("Pages active")),
				bytes.Equal(key, []byte("Pages inactive")),
				bytes.Equal(key, []byte("Pages speculative")),
				bytes.Equal(key, []byte("Pages wired down")),
				bytes.Equal(key, []byte("Pages occupied by compressor")):
				usedCached += val
			case bytes.Equal(key, []byte("Pages purgeable")),
				bytes.Equal(key, []byte("File-backed pages")):
				cached += val
			case bytes.Equal(key, []byte("Pages free")):
				free += val
			}
		}
		var used uint64
		if usedCached > cached {
			used = usedCached - cached
		}
		tot := usedCached + free
		if tot > 0 {
			ramTenths = int((used*1000 + tot/2) / tot)
		}
	}

	_ = os.MkdirAll(cacheDir, 0o755)
	var buf [96]byte
	b := strconv.AppendInt(buf[:0], now, 10)
	b = append(b, ' ')
	b = strconv.AppendInt(b, int64(cpuTenths), 10)
	b = append(b, ' ')
	b = strconv.AppendInt(b, int64(ramTenths), 10)
	b = append(b, '\n')
	tmp := cp + pidSuffix
	if err := os.WriteFile(tmp, b, 0o644); err == nil {
		_ = os.Rename(tmp, cp)
	}
	return cpuTenths, ramTenths
}
