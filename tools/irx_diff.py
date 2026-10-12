#!/usr/bin/env python3
"""Cross-engine differential check for the automata engines.

irx skips span and capture checks for patterns with a loop whose body can match empty on
Rust `regex`, Go `regexp`, RE2 and regex-automata, because their rule for such loops is not
modelled. These engines all document RE2's leftmost-first semantics, so this tool compares
them directly on exactly those patterns: same pattern, same subjects, capture mode (whole
match plus groups 1..6 of an unanchored search), and reports cases where they disagree.

usage: tools/irx_diff.py [--cases N] [--seed S] [--engines a,b,...] [--out DIR] [--all-patterns]

Patterns use only syntax with the same meaning in every engine (ASCII literals, `.`, small
classes, `^ $ \\b \\B`, groups, alternation, greedy and lazy quantifiers, inline flags i m s)
over ASCII subjects, so a disagreement is an engine difference rather than a dialect one.
By default every pattern contains a loop over a body that can match empty.
"""
import argparse, json, os, random, subprocess, sys, collections

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
B = os.path.join(ROOT, "hosts", "bin")
ENGINES = {
    "rust": ([f"{B}/regex_host", "capture"], {}),
    "pikevm": ([f"{B}/automata_host", "capture"], {"IRX_RA_ENGINE": "pikevm"}),
    "backtrack": ([f"{B}/automata_host", "capture"], {"IRX_RA_ENGINE": "backtrack"}),
    "lite": ([f"{B}/regex_lite_host", "capture"], {}),
    "go": ([f"{B}/go_host", "capture"], {}),
    "re2": ([f"{B}/re2_host", "capture"], {}),
    "pcre2": ([f"{B}/pcre2_host", "capture"], {}),  # reference (backtracking): expected to differ
    "re2j": (["/usr/bin/java", "-cp", f"{B}/re2j:{ROOT}/vendor/re2j/re2j-1.8.jar", "Re2jHost", "capture"], {}),
}

ATOMS = ["a", "a", "b", "b", ".", "[ab]", "[^a]", "\\b", "\\B", "^", "$", "(?:)", ""]


class Gen:
    def __init__(self, rng):
        self.r = rng
        self.groups = 0

    def group(self, body):
        if self.groups < 6 and self.r.random() < 0.6:
            self.groups += 1
            return f"({body})"
        return f"(?:{body})"

    def quant(self):
        q = self.r.choice(["*", "*", "+", "?", "{0,2}", "{1,3}", "{2}", "{0,}", "{2,}"])
        return q + ("?" if self.r.random() < 0.3 else "")

    def nullable(self, d):
        """A subexpression that can match empty."""
        k = self.r.randrange(4)
        if k == 0: return self.group(self.expr(d) + "|")
        if k == 1: return self.group("|" + self.expr(d))
        if k == 2: return self.group(self.expr(d)) + self.r.choice(["*", "?", "{0,2}"])
        return self.r.choice(["\\b", "\\B", "^", "$", "(?:)", self.group("")])

    def expr(self, d):
        if d <= 0: return self.r.choice(ATOMS)
        k = self.r.randrange(6)
        if k == 0: return self.expr(d - 1) + self.expr(d - 1)
        if k == 1: return self.expr(d - 1) + "|" + self.expr(d - 1)
        if k == 2: return self.group(self.expr(d - 1)) + self.quant()
        if k == 3: return self.group(self.nullable(d - 1)) + self.quant()  # loop over a nullable body
        if k == 4: return self.group(self.expr(d - 1))
        return self.r.choice(ATOMS)

    def pattern(self, force_nullable_loop):
        self.groups = 0
        p = self.expr(self.r.randrange(1, 4))
        if force_nullable_loop:
            loop = self.group(self.nullable(1)) + self.quant()
            p = self.r.choice([loop + p, p + loop, self.group(p + "|" + loop)])
        return p


def run_engine(name, cases):
    cmd, env = ENGINES[name]
    req = json.dumps([1, cases], ensure_ascii=True, separators=(",", ":")) + "\n"
    try:
        p = subprocess.run(cmd, input=req, capture_output=True, text=True, timeout=600, env={**os.environ, **env})
    except subprocess.TimeoutExpired:
        return None
    lines = [l for l in p.stdout.splitlines() if l.startswith("1 ")]
    if not lines: return None
    hexs = lines[-1].split(" ", 1)[1].strip()
    w = len(hexs) // len(cases)
    return [hexs[i * w:(i + 1) * w] for i in range(len(cases))]


def decode(h):
    """Hex result for one case -> (A spans, R spans) as lists of (s, e) or None; or 'fail:bits'."""
    if h.startswith("fe"): return f"fail:{h[2:4]}"
    vals = [int(h[i:i + 2], 16) for i in range(0, len(h), 2)]
    def spans(v):
        return [None if v[i] == 0xFF else (v[i], v[i + 1]) for i in range(0, len(v), 2)]
    half = len(vals) // 2
    return spans(vals[:half]), spans(vals[half:])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cases", type=int, default=5000)
    ap.add_argument("--batch", type=int, default=500)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--engines", default="rust,pikevm,backtrack,lite,go,re2,re2j")
    ap.add_argument("--all-patterns", action="store_true", help="do not force a nullable loop")
    ap.add_argument("--out", default=None)
    a = ap.parse_args()
    names = a.engines.split(",")
    rng = random.Random(a.seed)
    g = Gen(rng)
    groups = collections.defaultdict(list)
    compared = differ = errs = 0
    done = 0
    while done < a.cases:
        n = min(a.batch, a.cases - done)
        cases = []
        for _ in range(n):
            flags = rng.choice(["", "", "i", "m", "s", "ms"])
            subj = lambda: "".join(rng.choice("aab\n") for _ in range(rng.randrange(0, 6)))
            cases.append([flags, subj(), subj(), g.pattern(not a.all_patterns)])
        results = {e: run_engine(e, cases) for e in names}
        for e in names:
            if results[e] is None: print(f"warning: {e} produced no result for a batch", file=sys.stderr)
        for i, c in enumerate(cases):
            outs = {e: results[e][i] for e in names if results[e] is not None}
            if any(o.startswith("fe") for o in outs.values()):
                errs += 1
                if len({o.startswith("fe") for o in outs.values()}) > 1:
                    groups["compile/run error in some engines only: " + ",".join(sorted(e for e, o in outs.items() if o.startswith("fe")))].append((c, outs))
                continue
            compared += 1
            if len(set(outs.values())) > 1:
                differ += 1
                # Group by the partition of engines into agreeing classes.
                cls = collections.defaultdict(list)
                for e, o in outs.items(): cls[o].append(e)
                key = " | ".join(sorted("+".join(sorted(v)) for v in cls.values()))
                groups[key].append((c, outs))
        done += n
    print(f"compared {compared} cases ({errs} with an error somewhere), {differ} disagreements")
    for key, items in sorted(groups.items(), key=lambda kv: -len(kv[1])):
        print(f"\n== {len(items)} x  {key}")
        items.sort(key=lambda it: len(it[0][3]) + len(it[0][1]))
        for c, outs in items[:4]:
            print(f"   flags={c[0]!r} pattern={c[3]!r} A={c[1]!r} R={c[2]!r}")
            seen = {}
            for e, o in outs.items(): seen.setdefault(o, []).append(e)
            for o, es in seen.items():
                d = decode(o)
                print(f"      {'+'.join(es)}: {d if isinstance(d, str) else 'A=' + str([s for s in d[0] if s or True][:4]) + ' R=' + str(d[1][:4])}")
    if a.out:
        os.makedirs(a.out, exist_ok=True)
        with open(os.path.join(a.out, "diffs.json"), "w") as f:
            json.dump({k: v for k, v in groups.items()}, f, indent=1)


if __name__ == "__main__":
    main()
