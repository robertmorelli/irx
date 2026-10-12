// Go regexp host (RE2 syntax, linear time). Full match via \A(?:p)\z with inline flags.
package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"regexp"
	"runtime"
	"strings"
)

// loneSurrogate reports a \uD800-\uDFFF escape that is not part of a valid pair.
func loneSurrogate(raw string) bool {
	hexv := func(s string) (int, bool) {
		var v int
		if _, err := fmt.Sscanf(s, "%04x", &v); err != nil {
			return 0, false
		}
		return v, true
	}
	for i := 0; i+6 <= len(raw); i++ {
		if raw[i] != '\\' {
			continue
		}
		if raw[i+1] == '\\' {
			i++
			continue
		}
		if raw[i+1] != 'u' {
			continue
		}
		c, ok := hexv(raw[i+2 : i+6])
		if !ok || c < 0xD800 || c > 0xDFFF {
			continue
		}
		if c <= 0xDBFF && i+12 <= len(raw) && raw[i+6] == '\\' && raw[i+7] == 'u' {
			if d, ok := hexv(raw[i+8 : i+12]); ok && d >= 0xDC00 && d <= 0xDFFF {
				i += 11
				continue
			}
		}
		return true
	}
	return false
}

func main() {
	mode := "default"
	if len(os.Args) > 1 {
		mode = os.Args[1]
	}
	repeat := mode == "repeat" || mode == "tierup"
	wide = mode == "lspan" || mode == "lcapture"
	out := bufio.NewWriter(os.Stdout)
	fmt.Fprintf(out, "ready go-regexp-%s mode=%s\n", runtime.Version(), mode)
	out.Flush()
	in := bufio.NewReaderSize(os.Stdin, 1<<20)
	for {
		line, err := in.ReadString('\n')
		if len(line) == 0 && err != nil {
			return
		}
		var msg []json.RawMessage
		if json.Unmarshal([]byte(line), &msg) != nil || len(msg) != 2 {
			fmt.Fprintln(os.Stderr, "bad request")
			os.Exit(1)
		}
		var cases []json.RawMessage
		json.Unmarshal(msg[1], &cases)
		var sb strings.Builder
		sb.WriteString(strings.TrimSpace(string(msg[0])))
		sb.WriteByte(' ')
		for _, raw := range cases {
			var c [4]string
			json.Unmarshal(raw, &c)
			if mode == "capture" || mode == "lcapture" {
				if loneSurrogate(string(raw)) {
					sb.WriteString(failHex(0x40, 26))
				} else {
					sb.WriteString(capture(c[0], c[1], c[2], c[3]))
				}
				continue
			}
			if mode == "ospan" {
				// No start-offset search in regexp (slicing changes ^ and \b): unsupported.
				sb.WriteString(failHex(0x40, 2))
				continue
			}
			if mode == "span" || mode == "lspan" {
				if loneSurrogate(string(raw)) {
					sb.WriteString(failHex(0x40, 2))
				} else {
					sb.WriteString(span(c[0], c[1], c[2], c[3]))
				}
				continue
			}
			bits := 0
			if loneSurrogate(string(raw)) {
				bits = 0x40
			} else {
				bits = run(c[0], c[1], c[2], c[3], repeat)
			}
			fmt.Fprintf(&sb, "%02x", bits)
		}
		sb.WriteByte('\n')
		out.WriteString(sb.String())
		out.Flush()
	}
}

func run(flags, a, r, pat string, repeat bool) (bits int) {
	defer func() {
		if recover() != nil {
			bits = 0x08
		}
	}()
	pre := ""
	for _, f := range "ims" {
		if strings.ContainsRune(flags, f) {
			pre += string(f)
		}
	}
	if pre != "" {
		pre = "(?" + pre + ")"
	}
	re, err := regexp.Compile(pre + `\A(?:` + pat + `)\z`)
	if err != nil {
		return 0x04
	}
	reps := 1
	if repeat {
		reps = 2
	}
	for rep := 0; rep < reps; rep++ {
		for k, s := range []string{a, r} {
			if re.MatchString(s) {
				bits |= (1 << k) << (rep * 4)
			}
		}
	}
	return bits
}

// Long modes (lspan, lcapture): 4 hex digits per position, ffff = none, fffe + 00bb = failed.
var wide bool

func pairHex(s, e int) string {
	if wide {
		return fmt.Sprintf("%04x%04x", s, e)
	}
	return fmt.Sprintf("%02x%02x", s, e)
}

func noneHex() string {
	if wide {
		return "ffffffff"
	}
	return "ffff"
}

// failHex: failed case with bits b; rest = remaining positions after the first two.
func failHex(b, rest int) string {
	if wide {
		return fmt.Sprintf("fffe%04x", b) + strings.Repeat("0000", rest)
	}
	return fmt.Sprintf("fe%02x", b) + strings.Repeat("00", rest)
}

// span: unanchored search, byte offsets of the first match in A and R (src/span.zig).
func span(flags, a, r, pat string) (res string) {
	defer func() {
		if recover() != nil {
			res = failHex(8, 2)
		}
	}()
	pre := ""
	for _, f := range "ims" {
		if strings.ContainsRune(flags, f) {
			pre += string(f)
		}
	}
	if pre != "" {
		pre = "(?" + pre + ")"
	}
	re, err := regexp.Compile(pre + pat)
	if err != nil {
		return failHex(4, 2)
	}
	for _, s := range []string{a, r} {
		if m := re.FindStringIndex(s); m != nil {
			res += pairHex(m[0], m[1])
		} else {
			res += noneHex()
		}
	}
	return res
}

// capture: whole match + groups 1..6 per subject, byte offsets (src/capture.zig).
func capture(flags, a, r, pat string) (res string) {
	defer func() {
		if recover() != nil {
			res = failHex(8, 26)
		}
	}()
	pre := ""
	for _, f := range "ims" {
		if strings.ContainsRune(flags, f) {
			pre += string(f)
		}
	}
	if pre != "" {
		pre = "(?" + pre + ")"
	}
	re, err := regexp.Compile(pre + pat)
	if err != nil {
		return failHex(4, 26)
	}
	for _, s := range []string{a, r} {
		m := re.FindStringSubmatchIndex(s)
		for g := 0; g <= 6; g++ {
			if m != nil && 2*g+1 < len(m) && m[2*g] >= 0 {
				res += pairHex(m[2*g], m[2*g+1])
			} else {
				res += noneHex()
			}
		}
	}
	return res
}
