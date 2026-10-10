#!/usr/bin/env python3
"""Group a self-check mismatch dump: tools/mismatches.py findings/selfcheck-NAME [N]"""
import collections, json, sys
d = sys.argv[1]; n = int(sys.argv[2]) if len(sys.argv) > 2 else 40
groups = collections.defaultdict(list)
for line in open(f"{d}/selfcheck/mismatches.tsv", encoding="utf-8"):
    flags, kind, pat, a, model, eng = line.rstrip("\n").split("\t")
    groups[(kind, json.loads(pat), model, eng)].append((flags, json.loads(a)))
print(sum(len(v) for v in groups.values()), "mismatches in", len(groups), "groups")
for (kind, pat, model, eng), v in sorted(groups.items(), key=lambda kv: -len(kv[1]))[:n]:
    subj = sorted({repr(a) for _, a in v})
    fl = sorted({f for f, _ in v})
    print(f"{len(v):5} {kind:9} {pat!r:28} model={model} engine={eng} flags={','.join(fl)[:40]} subjects={' '.join(subj)[:120]}")
