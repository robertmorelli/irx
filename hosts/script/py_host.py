#!/usr/bin/env python3
"""irx host: Python `re`, or the third-party `regex` module (IRX_PY_ENGINE=regex; its default
VERSION0, which is compatible with `re`). Patterns arrive in Perl dialect; \\x{H} escapes become raw chars."""
import json, os, sys, time
if os.environ.get("IRX_PY_ENGINE") == "regex":
    import regex as re
    NAME = f"python-regex-{re.__version__}"
else:
    import re
    NAME = f"python-re-{sys.version.split()[0]}"
XESC = re.compile(r"\\x\{([0-9A-Fa-f]+)\}")
def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "default"
    rep = 2 if mode in ("repeat", "tierup") else 1
    # Long modes (lspan, lcapture): 4 hex digits per position, ffff = none, fffe + 00bb = failed.
    wide = mode in ("lspan", "lcapture")
    D = 4 if wide else 2
    NONE = "f" * (2 * D)
    P = lambda s, e: f"{s:0{D}x}{e:0{D}x}"
    FAIL = lambda b, rest: (f"fffe{b:04x}" if wide else f"fe{b:02x}") + "0" * (D * rest)
    is_span, is_cap = mode in ("span", "lspan", "ospan", "aspan"), mode in ("capture", "lcapture")
    print(f"ready {NAME} mode={mode}", flush=True)
    for line in sys.stdin:
        if not line.strip(): continue
        seq, cases = json.loads(line)
        out = []
        for flags, a, r, pat in cases:
            if mode == "bench":  # Shootout 2: "<flags>#<reps>"; compile once (cache purged), time searches
                flags, _, n = flags.partition("#"); n = max(1, int(n or 1))
                f = (re.I if "i" in flags else 0) | (re.M if "m" in flags else 0) | (re.S if "s" in flags else 0)
                re.purge(); t0 = time.perf_counter_ns()
                try: rx = re.compile(XESC.sub(lambda m: "\\U%08X" % int(m.group(1), 16), pat), f)
                except Exception: out.append("fe04" + "0" * 36); continue
                tc = time.perf_counter_ns() - t0
                try:
                    bits = (1 if rx.search(a) else 0) | (2 if rx.search(r) else 0)
                    s = rx.search; t1 = time.perf_counter_ns()
                    for _ in range(n): s(a)
                    t2 = time.perf_counter_ns()
                    for _ in range(n): s(r)
                    t3 = time.perf_counter_ns()
                except Exception: out.append("fe08" + "0" * 36); continue
                out.append(f"{bits:02x}{tc:012x}{t2 - t1:012x}{t3 - t2:012x}"); continue
            # ospan: "<flags>@<a>,<r>" = search start per subject (code points)
            starts = (0, 0)
            if "@" in flags: flags, o = flags.split("@", 1); starts = tuple(int(x) for x in o.split(","))
            if any(0xD800 <= ord(ch) <= 0xDFFF for ch in a + r + pat): out.append(FAIL(0x40, 2) if is_span else FAIL(0x40, 26) if is_cap else "40"); continue
            f = (re.I if "i" in flags else 0) | (re.M if "m" in flags else 0) | (re.S if "s" in flags else 0)
            if is_cap:  # whole match + groups 1..6 per subject (src/capture.zig)
                try: rx = re.compile(XESC.sub(lambda m: "\\U%08X" % int(m.group(1), 16), pat), f)
                except Exception: out.append(FAIL(4, 26)); continue
                try:
                    s = ""
                    for subj in (a, r):
                        m = rx.search(subj)
                        for g in range(7):
                            s += P(m.start(g), m.end(g)) if m and g <= rx.groups and m.start(g) >= 0 else NONE
                    out.append(s)
                except Exception: out.append(FAIL(8, 26))
                continue
            if is_span:  # unanchored search, code-point offsets (src/span.zig)
                try: rx = re.compile(XESC.sub(lambda m: "\\U%08X" % int(m.group(1), 16), pat), f)
                except Exception: out.append(FAIL(4, 2)); continue
                try:
                    s = ""
                    for subj, k in ((a, starts[0]), (r, starts[1])):
                        m = rx.match(subj, k) if mode == "aspan" else rx.search(subj, k)
                        s += P(m.start(), m.end()) if m else NONE
                    out.append(s)
                except Exception: out.append(FAIL(8, 2))
                continue
            try: rx = re.compile(r"\A(?:" + XESC.sub(lambda m: "\\U%08X" % int(m.group(1), 16), pat) + r")\Z", f)
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
