#!/usr/bin/env python3
"""irx host: Python `re`. Patterns arrive in Perl dialect; \\x{H} escapes become raw chars."""
import json, re, sys
XESC = re.compile(r"\\x\{([0-9A-Fa-f]+)\}")
def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "default"
    rep = 2 if mode in ("repeat", "tierup") else 1
    print(f"ready python-re-{sys.version.split()[0]} mode={mode}", flush=True)
    for line in sys.stdin:
        if not line.strip(): continue
        seq, cases = json.loads(line)
        out = []
        for flags, a, r, pat in cases:
            if any(0xD800 <= ord(ch) <= 0xDFFF for ch in a + r + pat): out.append("fe400000" if mode == "span" else "fe40" + "00" * 26 if mode == "capture" else "40"); continue
            f = (re.I if "i" in flags else 0) | (re.M if "m" in flags else 0) | (re.S if "s" in flags else 0)
            if mode == "capture":  # whole match + groups 1..6 per subject (src/capture.zig)
                try: rx = re.compile(XESC.sub(lambda m: chr(int(m.group(1), 16)), pat), f)
                except Exception: out.append("fe04" + "00" * 26); continue
                try:
                    s = ""
                    for subj in (a, r):
                        m = rx.search(subj)
                        for g in range(7):
                            s += f"{m.start(g):02x}{m.end(g):02x}" if m and g <= rx.groups and m.start(g) >= 0 else "ffff"
                    out.append(s)
                except Exception: out.append("fe08" + "00" * 26)
                continue
            if mode == "span":  # unanchored search, code-point offsets (src/span.zig)
                try: rx = re.compile(XESC.sub(lambda m: chr(int(m.group(1), 16)), pat), f)
                except Exception: out.append("fe040000"); continue
                try:
                    s = ""
                    for subj in (a, r):
                        m = rx.search(subj)
                        s += f"{m.start():02x}{m.end():02x}" if m else "ffff"
                    out.append(s)
                except Exception: out.append("fe080000")
                continue
            try: rx = re.compile(r"\A(?:" + XESC.sub(lambda m: chr(int(m.group(1), 16)), pat) + r")\Z", f)
            except Exception: out.append("04"); continue
            bits = 0
            try:
                for k in range(rep):
                    if rx.search(a): bits |= 1 << (4 * k)
                    if rx.search(r): bits |= 2 << (4 * k)
            except Exception: bits = 8
            out.append(f"{bits:02x}")
        print(f"{seq} {''.join(out)}", flush=True)
main()
