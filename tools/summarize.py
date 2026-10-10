#!/usr/bin/env python3
"""Summarize an irx campaign directory as a markdown results block.

usage: summarize.py OUTDIR NAME [TITLE] [LABEL]
Prints <!-- BEGIN NAME LABEL results --> ... block (LABEL defaults to "1m"): cases, findings by kind, self-check
mismatches, and the most common minimized shapes (from triage.json).
"""
import collections, json, os, re, sys

out, name = sys.argv[1], sys.argv[2]
title = sys.argv[3] if len(sys.argv) > 3 else name
label = sys.argv[4] if len(sys.argv) > 4 else "1m"
s = {}
try:
    s = json.load(open(f"{out}/summary.json"))
except Exception:
    pass
kinds = collections.Counter(); shapes = collections.Counter()
fdir = f"{out}/findings"
for f in (os.listdir(fdir) if os.path.isdir(fdir) else []):
    try:
        t = open(f"{fdir}/{f}/case.irx").read()
    except Exception:
        continue
    k = re.search(r"^kind=(\S+)", t, re.M).group(1)
    h = re.search(r"^history=(\S+)", t, re.M)
    kinds[k + ("" if not h or h.group(1) == "single-case" else f" ({h.group(1)})")] += 1
    try:
        m = json.load(open(f"{fdir}/{f}/triage.json")).get("minimized")
        if m:
            shapes[(k, m["flags"], json.dumps(m["A"], ensure_ascii=False), json.dumps(m["R"], ensure_ascii=False), m["pattern"], m["observed_bits"])] += 1
    except Exception:
        pass
sc = ""
try:
    log = open(f"{out}.log").read()
    m = re.search(r"selfcheck: (\d+) probes executed, (\d+) mismatches, (\d+) engine failures", log)
    if m: sc = f"self-check {int(m.group(1)):,} probes, {int(m.group(2)):,} mismatches, {m.group(3)} engine failures"
    if "unavailable (" in log or "required mode" in log or "engine not found" in log:
        sc += " | startup problem: " + "; ".join(l.strip() for l in log.splitlines() if "required mode" in l or "not found" in l)[:300]
except Exception:
    pass
lines = [f"<!-- BEGIN {name} {label} results -->", f"### {title}: {label} campaign", ""]
lines.append(f"* {s.get('cases', 0):,} patterns, {s.get('tables', 0)} tables, {s.get('distinct_findings', 0):,} distinct findings" + (f"; {sc}" if sc else ""))
if kinds:
    lines.append("* findings by kind: " + ", ".join(f"{v:,} {k}" for k, v in kinds.most_common()))
if shapes:
    lines += ["", "Most common minimized shapes (kind, flags, A, R, pattern, observed bits):", "", "| n | kind | flags | A | R | pattern | bits |", "|---|---|---|---|---|---|---|"]
    for (k, fl, a, r, p, b), v in shapes.most_common(8):
        lines.append(f"| {v} | {k} | `{fl}` | `{a}` | `{r}` | `{p.replace('|', chr(92) + '|')}` | {b} |")
lines += ["", "Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.", f"<!-- END {name} {label} results -->"]
print("\n".join(lines))
