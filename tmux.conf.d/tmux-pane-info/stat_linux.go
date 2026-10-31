//go:build linux

package main

import (
	"bytes"
	"context"
	"os"
	"os/exec"
	"strconv"
	"syscall"
	"time"
)

// statMtimeNs returns st's mtime in nanoseconds. Linux's syscall.Stat_t exposes
// this as the Mtim field (darwin uses Mtimespec instead — see stat_darwin.go).
func statMtimeNs(st *syscall.Stat_t) int64 {
	return st.Mtim.Sec*1e9 + st.Mtim.Nsec
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
	type gpuRes struct {
		m  gpuMetrics
		ok bool
	}
	gpuCh := make(chan gpuRes, 1)
	go func() {
		m, ok := linuxGPUMetrics()
		gpuCh <- gpuRes{m: m, ok: ok}
	}()

	inDocker := fileExists("/.dockerenv")
	isHost := !inDocker && isSystemdPid1()

	cpuTenths := linuxCPUTenths()
	var cpuTempC int
	var hasCPUTemp bool
	if !inDocker {
		cpuTempC, hasCPUTemp = linuxCPUTempC()
	}
	ramTenths := linuxRAMTenths()

	var usedGB, totalGB uint64
	var hasDisk bool
	if isHost {
		usedGB, totalGB, hasDisk = diskUsageGB()
	}

	kube := kubeSegment("green", "brightcyan")
	gr := <-gpuCh

	os.Stdout.Write(buildRightStatus(
		cpuTenths,
		cpuTempC, hasCPUTemp,
		ramTenths,
		gr.m, gr.ok,
		usedGB, totalGB, hasDisk,
		kube,
	))
}

func fileExists(path string) bool {
	var st syscall.Stat_t
	return syscall.Stat(path, &st) == nil
}

func readSmallFile(path string, buf []byte) ([]byte, bool) {
	fd, err := syscall.Open(path, syscall.O_RDONLY, 0)
	if err != nil {
		return nil, false
	}
	n, err := syscall.Read(fd, buf)
	syscall.Close(fd)
	if err != nil || n <= 0 {
		return nil, false
	}
	return buf[:n], true
}

func isSystemdPid1() bool {
	var buf [32]byte
	data, ok := readSmallFile("/proc/1/comm", buf[:])
	if !ok {
		return false
	}
	return bytes.Equal(bytes.TrimSpace(data), []byte("systemd"))
}

func readProcStat() (total, idle uint64, ok bool) {
	var buf [512]byte
	data, valid := readSmallFile("/proc/stat", buf[:])
	if !valid {
		return 0, 0, false
	}
	return parseProcStatCPU(data)
}

func linuxCPUTenths() int {
	curTotal, curIdle, ok := readProcStat()
	if !ok {
		return 0
	}
	now := time.Now().UnixNano()
	cp := cacheDir + "/tmux-cpu-stat"

	var cbuf [128]byte
	if cdata, cok := readSmallFile(cp, cbuf[:]); cok {
		prevNano, r1, ok1 := parseUintField(cdata)
		prevTotal, r2, ok2 := parseUintField(r1)
		prevIdle, r3, ok3 := parseUintField(r2)
		lastTenths, _, ok4 := parseUintField(r3)
		if ok1 && ok2 && ok3 {
			age := now - int64(prevNano)
			// Reuse recent reading (<500ms) so multiple tmux servers sharing ~/.cache do not thrash
			if age >= 0 && age < int64(500*time.Millisecond) && ok4 {
				return int(lastTenths)
			}
			if age >= int64(500*time.Millisecond) && age <= int64(30*time.Second) {
				if tenths, valid := calcCPUTenths(prevTotal, prevIdle, curTotal, curIdle); valid {
					writeCPUStatCache(cp, now, curTotal, curIdle, tenths)
					return tenths
				}
			}
		}
	}

	// Cold start or stale (>30s): take a short 15ms delta instead of blocking 1000ms like iostat
	time.Sleep(15 * time.Millisecond)
	curTotal2, curIdle2, ok2 := readProcStat()
	now2 := time.Now().UnixNano()
	if !ok2 {
		writeCPUStatCache(cp, now, curTotal, curIdle, 0)
		return 0
	}
	tenths, _ := calcCPUTenths(curTotal, curIdle, curTotal2, curIdle2)
	writeCPUStatCache(cp, now2, curTotal2, curIdle2, tenths)
	return tenths
}

func writeCPUStatCache(cp string, nowNano int64, total, idle uint64, tenths int) {
	_ = os.MkdirAll(cacheDir, 0o755)
	var buf [128]byte
	b := strconv.AppendInt(buf[:0], nowNano, 10)
	b = append(b, ' ')
	b = strconv.AppendUint(b, total, 10)
	b = append(b, ' ')
	b = strconv.AppendUint(b, idle, 10)
	b = append(b, ' ')
	b = strconv.AppendInt(b, int64(tenths), 10)
	b = append(b, '\n')
	tmp := cp + pidSuffix
	if err := os.WriteFile(tmp, b, 0o644); err == nil {
		_ = os.Rename(tmp, cp)
	}
}

func linuxRAMTenths() int {
	var buf [1024]byte
	data, ok := readSmallFile("/proc/meminfo", buf[:])
	if !ok {
		return 0
	}
	tenths, _ := parseMeminfoTenths(data)
	return tenths
}

// linuxCPUTempC reads CPU die/core temperature directly from /sys/class/hwmon
// without spawning `sensors`. Matches tmux-cpu's `Core *` / `Tccd*` average.
func linuxCPUTempC() (int, bool) {
	var buf [64]byte
	fallbackC := -1

	for h := 0; h < 16; h++ {
		dir := "/sys/class/hwmon/hwmon" + strconv.Itoa(h)
		nameBytes, ok := readSmallFile(dir+"/name", buf[:])
		if !ok {
			continue
		}
		name := string(bytes.TrimSpace(nameBytes))
		isPrimary := name == "coretemp" || name == "k10temp" || name == "zenpower"
		isFallback := name == "cpu_thermal" || name == "acpitz"
		if !isPrimary && !isFallback {
			continue
		}

		var sumMilli, count int64
		var pkgMilli int64 = -1

		for idx := 1; idx <= 32; idx++ {
			prefix := dir + "/temp" + strconv.Itoa(idx)
			valBytes, vok := readSmallFile(prefix+"_input", buf[:])
			if !vok {
				continue
			}
			milli, _, pok := parseUintField(valBytes)
			if !pok || milli == 0 {
				continue
			}
			if pkgMilli < 0 {
				pkgMilli = int64(milli)
			}
			if !isPrimary {
				continue
			}
			lblBytes, lok := readSmallFile(prefix+"_label", buf[:])
			if !lok {
				continue
			}
			lbl := bytes.TrimSpace(lblBytes)
			if bytes.HasPrefix(lbl, []byte("Core ")) || bytes.HasPrefix(lbl, []byte("Tccd")) {
				sumMilli += int64(milli)
				count++
			}
		}

		if count > 0 {
			avgMilli := sumMilli / count
			return int((avgMilli + 500) / 1000), true
		}
		if isPrimary && pkgMilli > 0 {
			return int((pkgMilli + 500) / 1000), true
		}
		if fallbackC < 0 && pkgMilli > 0 {
			fallbackC = int((pkgMilli + 500) / 1000)
		}
	}

	if fallbackC >= 0 {
		return fallbackC, true
	}
	return 0, false
}

func linuxGPUMetrics() (gpuMetrics, bool) {
	cp := cacheDir + "/tmux-gpu-out"
	now := time.Now().UnixNano()

	var cbuf [128]byte
	if cdata, cok := readSmallFile(cp, cbuf[:]); cok {
		ts, rest, ok1 := parseUintField(cdata)
		if ok1 {
			age := now - int64(ts)
			rest = bytes.TrimSpace(rest)
			if bytes.Equal(rest, []byte("none")) {
				if age >= 0 && age < int64(60*time.Second) {
					return gpuMetrics{}, false
				}
			} else if age >= 0 && age < int64(3*time.Second) {
				g, r1, ok2 := parseUintField(rest)
				hasT, r2, ok3 := parseUintField(r1)
				t, r3, ok4 := parseUintField(r2)
				hasV, r4, ok5 := parseUintField(r3)
				v, _, ok6 := parseUintField(r4)
				if ok2 && ok3 && ok4 && ok5 && ok6 {
					return gpuMetrics{
						gpuTenths:  int(g),
						tempC:      int(t),
						vramTenths: int(v),
						hasTemp:    hasT == 1,
						hasVRAM:    hasV == 1,
					}, true
				}
			}
		}
	}

	if fileExists("/dev/nvidiactl") {
		ctx, cancel := context.WithTimeout(context.Background(), 1500*time.Millisecond)
		out, err := exec.CommandContext(
			ctx,
			"nvidia-smi",
			"--query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total",
			"--format=csv,noheader,nounits",
		).Output()
		cancel()
		if err == nil {
			if m, ok := parseNvidiaCSV(out); ok {
				writeGPUCache(cp, now, m, true)
				return m, true
			}
		}
	}

	if m, ok := amdSysfsGPU(); ok {
		writeGPUCache(cp, now, m, true)
		return m, true
	}

	writeGPUCache(cp, now, gpuMetrics{}, false)
	return gpuMetrics{}, false
}

func amdSysfsGPU() (gpuMetrics, bool) {
	var buf [64]byte
	for card := 0; card < 4; card++ {
		dev := "/sys/class/drm/card" + strconv.Itoa(card) + "/device"
		busyBytes, ok := readSmallFile(dev+"/gpu_busy_percent", buf[:])
		if !ok {
			continue
		}
		busy, _, pok := parseUintField(busyBytes)
		if !pok {
			continue
		}
		m := gpuMetrics{gpuTenths: int(busy) * 10}

		if usedB, uok := readSmallFile(dev+"/mem_info_vram_used", buf[:]); uok {
			used, _, ok1 := parseUintField(usedB)
			if totB, tok := readSmallFile(dev+"/mem_info_vram_total", buf[:]); tok && ok1 {
				tot, _, ok2 := parseUintField(totB)
				if ok2 && tot > 0 {
					m.vramTenths = int((used*1000 + tot/2) / tot)
					m.hasVRAM = true
				}
			}
		}
		for h := 0; h < 8; h++ {
			tB, tok := readSmallFile(dev+"/hwmon/hwmon"+strconv.Itoa(h)+"/temp1_input", buf[:])
			if !tok {
				continue
			}
			if milli, _, ok1 := parseUintField(tB); ok1 && milli > 0 {
				m.tempC = int((milli + 500) / 1000)
				m.hasTemp = true
				break
			}
		}
		return m, true
	}
	return gpuMetrics{}, false
}

func writeGPUCache(cp string, nowNano int64, m gpuMetrics, present bool) {
	_ = os.MkdirAll(cacheDir, 0o755)
	var buf [128]byte
	b := strconv.AppendInt(buf[:0], nowNano, 10)
	if !present {
		b = append(b, " none\n"...)
	} else {
		hasT := uint64(0)
		if m.hasTemp {
			hasT = 1
		}
		hasV := uint64(0)
		if m.hasVRAM {
			hasV = 1
		}
		b = append(b, ' ')
		b = strconv.AppendInt(b, int64(m.gpuTenths), 10)
		b = append(b, ' ')
		b = strconv.AppendUint(b, hasT, 10)
		b = append(b, ' ')
		b = strconv.AppendInt(b, int64(m.tempC), 10)
		b = append(b, ' ')
		b = strconv.AppendUint(b, hasV, 10)
		b = append(b, ' ')
		b = strconv.AppendInt(b, int64(m.vramTenths), 10)
		b = append(b, '\n')
	}
	tmp := cp + pidSuffix
	if err := os.WriteFile(tmp, b, 0o644); err == nil {
		_ = os.Rename(tmp, cp)
	}
}
