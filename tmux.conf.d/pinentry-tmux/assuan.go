package main

import (
	"bytes"
	"fmt"
	"strconv"
)

func assuanDecode(s []byte) string {
	var b bytes.Buffer
	b.Grow(len(s))
	for i := 0; i < len(s); i++ {
		if s[i] == '%' && i+2 < len(s) {
			hi, e1 := strconv.ParseUint(string(s[i+1:i+2]), 16, 8)
			lo, e2 := strconv.ParseUint(string(s[i+2:i+3]), 16, 8)
			if e1 == nil && e2 == nil {
				b.WriteByte(byte(hi<<4 | lo))
				i += 2
				continue
			}
		}
		b.WriteByte(s[i])
	}
	return b.String()
}

func assuanEncode(s []byte) []byte {
	var b bytes.Buffer
	b.Grow(len(s))
	for i := 0; i < len(s); i++ {
		c := s[i]
		if c < 0x20 || c == '%' || c > 0x7e {
			fmt.Fprintf(&b, "%%%02X", c)
		} else {
			b.WriteByte(c)
		}
	}
	return b.Bytes()
}
