#!/usr/bin/env python3
"""Ask a shell host a few ad-hoc questions: probe.py <target> 'flags|A|R|pattern' ...
A/R/pattern accept Python escapes (\\n, \\u2028). Prints the two result bits per case
(A, R) or ERR/EXC. Handy when writing a dialect model."""
import json, subprocess, sys, tomllib, os
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
t = tomllib.load(open(f"{root}/targets/{sys.argv[1]}/target.toml", "rb"))["target"]
cmd = t["command"].replace("{root}", root).replace("{home}", os.path.expanduser("~")).replace("{mode}", "interp").replace("{driver}", f"{root}/driver.js")
cases = []
for arg in sys.argv[2:]:
    f, a, r, p = arg.split("|", 3)
    dec = lambda s: s.encode("latin-1", "backslashreplace").decode("unicode_escape")
    cases.append([f, dec(a), dec(r), dec(p)])
proc = subprocess.Popen(cmd, shell=True, stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, encoding="utf-8")
out, _ = proc.communicate(json.dumps([1, cases], separators=(",", ":")) + "\n", timeout=60)
line = [l for l in out.splitlines() if l.startswith("1 ")][-1].split()[1]
for i, c in enumerate(cases):
    b = int(line[2 * i:2 * i + 2], 16)
    res = "ERR" if b & 4 else "EXC" if b & 8 else "UNS" if b & 64 else f"A={b & 1} R={(b >> 1) & 1}"
    print(f"{res:10} {sys.argv[2 + i]}")
