//go:build linux

package main

import "testing"

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
