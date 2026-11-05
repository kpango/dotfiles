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
	"unsafe"
)

// atFdcwd represents AT_FDCWD (-100) safely without Go compiler constant overflow.
const atFdcwd = ^uintptr(99)

var (
	dockerenvPathNT   = []byte("/.dockerenv\x00")
	proc1CommPathNT   = []byte("/proc/1/comm\x00")
	procStatPathNT    = []byte("/proc/stat\x00")
	procMeminfoPathNT = []byte("/proc/meminfo\x00")
	nvidiactlPathNT   = []byte("/dev/nvidiactl\x00")

	cpuStatPathNT    []byte
	hwmonCachePathNT []byte
	gpuOutPathNT     []byte
)

// statBuf stats the path given as a null-terminated byte slice using SYS_NEWFSTATAT/SYS_FSTATAT.
func statBuf(path []byte, st *syscall.Stat_t) syscall.Errno {
	if len(path) == 0 {
		return syscall.EINVAL
	}
	_, _, errno := syscall.Syscall6(
		sysFstatat,
		atFdcwd,
		uintptr(unsafe.Pointer(&path[0])),
		uintptr(unsafe.Pointer(st)),
		0,
		0,
		0,
	)
	return errno
}

// openBuf opens the path given as a null-terminated byte slice using SYS_OPENAT.
func openBuf(path []byte, flags int) (int, syscall.Errno) {
	if len(path) == 0 {
		return -1, syscall.EINVAL
	}
	r0, _, errno := syscall.Syscall6(
		syscall.SYS_OPENAT,
		atFdcwd,
		uintptr(unsafe.Pointer(&path[0])),
		uintptr(flags|syscall.O_LARGEFILE),
		0,
		0,
		0,
	)
	if errno != 0 {
		return -1, errno
	}
	return int(r0), 0
}

func init() {
	cpuStatPathNT = append([]byte(cacheDir+"/tmux-cpu-stat"), 0)
	hwmonCachePathNT = append([]byte(cacheDir+"/tmux-cpu-hwmon"), 0)
	gpuOutPathNT = append([]byte(cacheDir+"/tmux-gpu-out"), 0)

	if len(os.Args) == 2 && os.Args[1] == "--refresh-gpu" {
		updateGPUCacheSync()
		os.Exit(0)
	}
}

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
	gpu, hasGPU := linuxGPUMetrics()

	inDocker := fileExistsNT(dockerenvPathNT)
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

	var buf [512]byte
	os.Stdout.Write(buildRightStatus(
		buf[:0],
		cpuTenths,
		cpuTempC, hasCPUTemp,
		ramTenths,
		gpu, hasGPU,
		usedGB, totalGB, hasDisk,
		kube,
	))
}

func fileExists(path string) bool {
	var st syscall.Stat_t
	return syscall.Stat(path, &st) == nil
}

func fileExistsNT(pathNT []byte) bool {
	var st syscall.Stat_t
	return statBuf(pathNT, &st) == 0
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

func readSmallFileNT(pathNT []byte, buf []byte) ([]byte, bool) {
	fd, errno := openBuf(pathNT, syscall.O_RDONLY)
	if errno != 0 {
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
	data, ok := readSmallFileNT(proc1CommPathNT, buf[:])
	if !ok {
		return false
	}
	return bytes.Equal(bytes.TrimSpace(data), []byte("systemd"))
}

func readProcStat() (total, idle uint64, ok bool) {
	var buf [512]byte
	data, valid := readSmallFileNT(procStatPathNT, buf[:])
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
	if cdata, cok := readSmallFileNT(cpuStatPathNT, cbuf[:]); cok {
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

	// Cold start or stale (>30s): record baseline snapshot without blocking.
	// The next tmux status tick (5s) will compute the accurate delta.
	writeCPUStatCache(cp, now, curTotal, curIdle, 0)
	return 0
}

func writeCPUStatCache(cp string, nowNano int64, total, idle uint64, tenths int) {
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
	} else if os.IsNotExist(err) {
		_ = os.MkdirAll(cacheDir, 0o755)
		if err := os.WriteFile(tmp, b, 0o644); err == nil {
			_ = os.Rename(tmp, cp)
		}
	}
}

func linuxRAMTenths() int {
	var buf [1024]byte
	data, ok := readSmallFileNT(procMeminfoPathNT, buf[:])
	if !ok {
		return 0
	}
	tenths, _ := parseMeminfoTenths(data)
	return tenths
}

var (
	cachedHwmonH       = -1
	cachedHwmonIndices []int
)

// linuxCPUTempC reads CPU die/core temperature directly from /sys/class/hwmon
// without spawning `sensors`. Matches tmux-cpu's `Core *` / `Tccd*` average.
func linuxCPUTempC() (int, bool) {
	var buf [64]byte

	// 1. In-memory fast path
	if cachedHwmonH >= 0 {
		if temp, ok := readHwmonTemps(cachedHwmonH, cachedHwmonIndices, buf[:]); ok {
			return temp, true
		}
		cachedHwmonH = -1
		cachedHwmonIndices = nil
	}

	// 2. Persistent cache fast path (~/.cache/tmux-cpu-hwmon)
	hwmonCache := cacheDir + "/tmux-cpu-hwmon"
	var cbuf [64]byte
	if cdata, cok := readSmallFileNT(hwmonCachePathNT, cbuf[:]); cok {
		if hVal, rest, ok1 := parseUintField(cdata); ok1 {
			var indices []int
			for {
				idxVal, nextRest, ok2 := parseUintField(rest)
				if !ok2 {
					break
				}
				indices = append(indices, int(idxVal))
				rest = nextRest
			}
			if len(indices) > 0 {
				if temp, ok := readHwmonTemps(int(hVal), indices, buf[:]); ok {
					cachedHwmonH = int(hVal)
					cachedHwmonIndices = indices
					return temp, true
				}
			}
		}
	}

	// 3. Sysfs scan with early-exit on non-existent sensor indices
	fallbackC := -1

	for h := 0; h < 16; h++ {
		var dbuf [64]byte
		d := append(dbuf[:0], "/sys/class/hwmon/hwmon"...)
		d = strconv.AppendInt(d, int64(h), 10)
		nameNT := append(d, "/name\x00"...)
		nameBytes, ok := readSmallFileNT(nameNT, buf[:])
		if !ok {
			continue
		}
		name := bytes.TrimSpace(nameBytes)
		isPrimary := bytes.Equal(name, []byte("coretemp")) || bytes.Equal(name, []byte("k10temp")) || bytes.Equal(name, []byte("zenpower"))
		isFallback := bytes.Equal(name, []byte("cpu_thermal")) || bytes.Equal(name, []byte("acpitz"))
		if !isPrimary && !isFallback {
			continue
		}

		var sumMilli, count int64
		var pkgMilli int64 = -1
		var foundIndices []int
		missCount := 0

		for idx := 1; idx <= 32; idx++ {
			p := append(dbuf[:0], "/sys/class/hwmon/hwmon"...)
			p = strconv.AppendInt(p, int64(h), 10)
			p = append(p, "/temp"...)
			p = strconv.AppendInt(p, int64(idx), 10)
			pLen := len(p)

			p = append(p, "_input\x00"...)
			valBytes, vok := readSmallFileNT(p, buf[:])
			if !vok {
				missCount++
				// Fast path: AMD k10temp skips temp2 but temp3..10 are contiguous.
				// Break immediately on 2 consecutive misses or when missing after finding cores.
				if missCount >= 2 || (count > 0 && idx > 2) {
					break
				}
				continue
			}
			missCount = 0

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

			p = append(p[:pLen], "_label\x00"...)
			lblBytes, lok := readSmallFileNT(p, buf[:])
			if !lok {
				continue
			}
			lbl := bytes.TrimSpace(lblBytes)
			if bytes.HasPrefix(lbl, []byte("Core ")) || bytes.HasPrefix(lbl, []byte("Tccd")) {
				sumMilli += int64(milli)
				count++
				foundIndices = append(foundIndices, idx)
			}
		}

		if isPrimary && count > 0 {
			cachedHwmonH = h
			cachedHwmonIndices = foundIndices
			writeHwmonCache(hwmonCache, h, foundIndices)
			avgMilli := sumMilli / count
			return int((avgMilli + 500) / 1000), true
		}
		if isPrimary && pkgMilli > 0 {
			cachedHwmonH = h
			cachedHwmonIndices = []int{1}
			writeHwmonCache(hwmonCache, h, []int{1})
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

func readHwmonTemps(h int, indices []int, buf []byte) (int, bool) {
	var sumMilli, count int64
	var dbuf [64]byte
	d := append(dbuf[:0], "/sys/class/hwmon/hwmon"...)
	d = strconv.AppendInt(d, int64(h), 10)
	d = append(d, "/temp"...)
	dLen := len(d)

	for _, idx := range indices {
		p := strconv.AppendInt(d[:dLen], int64(idx), 10)
		p = append(p, "_input\x00"...)
		valBytes, ok := readSmallFileNT(p, buf)
		if !ok {
			return 0, false
		}
		milli, _, pok := parseUintField(valBytes)
		if !pok || milli == 0 {
			return 0, false
		}
		sumMilli += int64(milli)
		count++
	}
	if count == 0 {
		return 0, false
	}
	return int(((sumMilli / count) + 500) / 1000), true
}

func writeHwmonCache(cp string, h int, indices []int) {
	var buf [64]byte
	b := strconv.AppendInt(buf[:0], int64(h), 10)
	for _, idx := range indices {
		b = append(b, ' ')
		b = strconv.AppendInt(b, int64(idx), 10)
	}
	b = append(b, '\n')
	tmp := cp + pidSuffix
	if err := os.WriteFile(tmp, b, 0o644); err == nil {
		_ = os.Rename(tmp, cp)
	} else if os.IsNotExist(err) {
		_ = os.MkdirAll(cacheDir, 0o755)
		if err := os.WriteFile(tmp, b, 0o644); err == nil {
			_ = os.Rename(tmp, cp)
		}
	}
}

func linuxGPUMetrics() (gpuMetrics, bool) {
	cp := cacheDir + "/tmux-gpu-out"
	now := time.Now().UnixNano()
	const freshTTL = int64(12 * time.Second)
	const staleTTL = int64(60 * time.Second)

	var cbuf [128]byte
	if cdata, cok := readSmallFileNT(gpuOutPathNT, cbuf[:]); cok {
		ts, rest, ok1 := parseUintField(cdata)
		if ok1 {
			age := now - int64(ts)
			rest = bytes.TrimSpace(rest)
			if bytes.Equal(rest, []byte("none")) {
				if age >= 0 && age < int64(60*time.Second) {
					return gpuMetrics{}, false
				}
			} else {
				g, r1, ok2 := parseUintField(rest)
				hasT, r2, ok3 := parseUintField(r1)
				t, r3, ok4 := parseUintField(r2)
				hasV, r4, ok5 := parseUintField(r3)
				v, _, ok6 := parseUintField(r4)
				if ok2 && ok3 && ok4 && ok5 && ok6 {
					cached := gpuMetrics{
						gpuTenths:  int(g),
						tempC:      int(t),
						vramTenths: int(v),
						hasTemp:    hasT == 1,
						hasVRAM:    hasV == 1,
					}
					if age >= 0 && age < freshTTL {
						return cached, true
					}
					if age >= freshTTL && age < staleTTL {
						// Atomic lease: update timestamp to prevent multiple concurrent spawns
						writeGPUCache(cp, now, cached, true)
						spawnGPURefresh()
						return cached, true
					}
				}
			}
		}
	}

	if m, ok := amdSysfsGPU(); ok {
		writeGPUCache(cp, now, m, true)
		return m, true
	}

	if fileExistsNT(nvidiactlPathNT) {
		// Cold start seed: synchronous initial query
		if m, ok := queryNvidiaGPU(); ok {
			writeGPUCache(cp, now, m, true)
			return m, true
		}
	}

	writeGPUCache(cp, now, gpuMetrics{}, false)
	return gpuMetrics{}, false
}

func amdSysfsGPU() (gpuMetrics, bool) {
	var buf [64]byte
	var devBuf [64]byte
	for card := 0; card < 4; card++ {
		dev := append(devBuf[:0], "/sys/class/drm/card"...)
		dev = strconv.AppendInt(dev, int64(card), 10)
		dev = append(dev, "/device"...)
		devLen := len(dev)

		busyBytes, ok := readSmallFileNT(append(dev[:devLen], "/gpu_busy_percent\x00"...), buf[:])
		if !ok {
			continue
		}
		busy, _, pok := parseUintField(busyBytes)
		if !pok {
			continue
		}
		m := gpuMetrics{gpuTenths: int(busy) * 10}

		if usedB, uok := readSmallFileNT(append(dev[:devLen], "/mem_info_vram_used\x00"...), buf[:]); uok {
			used, _, ok1 := parseUintField(usedB)
			if totB, tok := readSmallFileNT(append(dev[:devLen], "/mem_info_vram_total\x00"...), buf[:]); tok && ok1 {
				tot, _, ok2 := parseUintField(totB)
				if ok2 && tot > 0 {
					m.vramTenths = int((used*1000 + tot/2) / tot)
					m.hasVRAM = true
				}
			}
		}
		for h := 0; h < 8; h++ {
			hw := append(dev[:devLen], "/hwmon/hwmon"...)
			hw = strconv.AppendInt(hw, int64(h), 10)
			hw = append(hw, "/temp1_input\x00"...)
			tB, tok := readSmallFileNT(hw, buf[:])
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
	} else if os.IsNotExist(err) {
		_ = os.MkdirAll(cacheDir, 0o755)
		if err := os.WriteFile(tmp, b, 0o644); err == nil {
			_ = os.Rename(tmp, cp)
		}
	}
}

func queryNvidiaGPU() (gpuMetrics, bool) {
	if !fileExistsNT(nvidiactlPathNT) {
		return gpuMetrics{}, false
	}

	ctx, cancel := context.WithTimeout(context.Background(), 1500*time.Millisecond)
	defer cancel()
	out, err := exec.CommandContext(
		ctx,
		"nvidia-smi",
		"--query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total",
		"--format=csv,noheader,nounits",
	).Output()
	if err != nil {
		return gpuMetrics{}, false
	}
	return parseNvidiaCSV(out)
}

func updateGPUCacheSync() {
	now := time.Now().UnixNano()
	cp := cacheDir + "/tmux-gpu-out"
	if m, ok := queryNvidiaGPU(); ok {
		writeGPUCache(cp, now, m, true)
		return
	}
	if m, ok := amdSysfsGPU(); ok {
		writeGPUCache(cp, now, m, true)
		return
	}
	writeGPUCache(cp, now, gpuMetrics{}, false)
}

func spawnGPURefresh() {
	execPath, err := os.Executable()
	if err != nil {
		return
	}
	cmd := exec.Command(execPath, "--refresh-gpu")
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	cmd.Stdin = nil
	cmd.Stdout = nil
	cmd.Stderr = nil
	_ = cmd.Start()
}
