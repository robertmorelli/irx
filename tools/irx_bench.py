#!/usr/bin/env python3
"""Shootout 2: speed of every irx engine on one shared workload, through the hosts' "bench" mode.

usage: tools/irx_bench.py run [--engines a,b] [--patterns N] [--seed S] [--out DIR]
       tools/irx_bench.py report [--out DIR]

Workload: random patterns written in syntax nearly every engine accepts (literals, `.`, small
classes and ranges, \\d \\w \\s, groups, alternation, greedy/lazy/counted quantifiers, a few
anchors and \\b), in two sets: ASCII (ASCII literals and subjects) and Unicode (non-ASCII literals
including an astral character, mixed subjects). Each pattern is paired with subjects in four size
bins; per bin, A embeds a string generated from the pattern (usually a match) in random filler and R
is filler plus a shuffled copy (usually not). Whether an input matched is taken from Rust `regex`,
the reference, so "accept" and "reject" mean the same inputs for every engine.

Each case goes to the host as [flags#reps, A, R, pattern]; the host compiles once (timed), runs one
untimed search per subject, then times `reps` unanchored "is there a match?" searches of A and of R
(see hosts/c/proto.h). One case per request, so a hang costs one case: the host is killed after
--timeout seconds and restarted. Results are written per engine (resumable); `report` computes
each engine's geometric-mean time relative to Rust on the inputs both ran, overall and split by
set, outcome and size bin.
"""
import argparse, json, math, os, random, re, select, subprocess, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HOME = os.path.expanduser("~")

# (name, irx target, family, mode override or None, extra executable flags for d8)
ENGINES = [
    ("rust-regex", "rust-regex", "Rust", None), ("regex-lite", "regex-lite", "Rust", None),
    ("ra-pikevm", "ra-pikevm", "Rust", None), ("ra-backtrack", "ra-backtrack", "Rust", None),
    ("ra-hybrid", "ra-hybrid", "Rust", None), ("ra-dfa", "ra-dfa", "Rust", None),
    ("fancy-regex", "fancy-regex", "Rust", None), ("resharp", "resharp", "Rust", None),
    ("pcre2", "pcre2", "C", None), ("pcre2-jit", "pcre2-jit", "C", None),
    ("pcre1", "pcre1", "C", None),  # Homebrew PCRE1 8.45 has no JIT on arm64 (pcre1-jit runs the interpreter)
    ("oniguruma", "oniguruma", "C", None), ("re2", "re2", "C", None), ("icu-c", "icu-c", "C", None),
    ("vectorscan", "vectorscan", "C", None), ("llvm-regex", "llvm-regex", "C", None),
    ("libc-regex", "libc-regex", "C", None), ("gnu-regex", "gnu-regex", "C", None), ("minrx", "minrx", "C", None),
    ("cpp-regex", "cpp-regex", "C", None), ("boost-regex", "boost-regex", "C", None),
    ("v8", "v8", "JS", None), ("v8-linear", "v8-linear", "JS", "benchlinear"), ("spidermonkey", "spidermonkey", "JS", None),
    ("jsc", "jsc", "JS", None), ("bun", "bun", "JS", None), ("quickjs", "quickjs", "JS", None),
    ("graaljs", "graaljs", "JS", None), ("boa", "boa", "JS", None), ("xs", "xs", "JS", None), ("hermes", "hermes", "JS", None),
    ("python-re", "python-re", "Script", None), ("python-regex", "python-regex", "Script", None),
    ("ruby-onigmo", "ruby-onigmo", "Script", None), ("perl", "perl", "Script", None),
    ("php-pcre2", "php-pcre2", "Script", None), ("tcl", "tcl", "Script", None),
    ("java", "java", "VM", None), ("re2j", "re2j", "VM", None),
    ("dotnet-interp", "dotnet-interp", "VM", None), ("dotnet-compiled", "dotnet-compiled", "VM", None),
    ("dotnet-nonbacktracking", "dotnet-nonbacktracking", "VM", None), ("go-regexp", "go-regexp", "VM", None),
    ("swift-regex", "swift-regex", "VM", None), ("icu", "icu", "VM", None),
    ("erlang-re", "erlang-re", "VM", None), ("racket", "racket", "VM", None), ("emacs", "emacs", "VM", None),
    ("nim-regex", "nim-regex", "VM", None),
]
BINS = [("tiny", 16, 3000), ("small", 128, 600), ("medium", 1024, 80), ("large", 8192, 12)]
MIN_LOOP_NS = 2_000_000
D8_FLAGS = {"v8-linear": ["--enable-experimental-regexp-engine"]}


def target_meta(t):
    s = open(os.path.join(ROOT, "targets", t, "target.toml")).read()
    g = lambda k, d="": (re.search(r'^' + k + r' = "(.*?)"', s, re.M) or [None, d])[1]
    return g("kind", "shell"), g("command"), g("env")


def command(name, target, mode):
    kind, cmd, env = target_meta(target)
    sub = lambda c: c.replace("{root}", ROOT).replace("{home}", HOME)
    driver = os.path.join(ROOT, "driver.pl" if kind == "perl" else "driver.js")
    if kind == "d8": argv = [sub(cmd)] + D8_FLAGS.get(name, []) + [driver, "--", mode]
    elif kind == "perl": argv = [sub(cmd), driver, mode]
    else: argv = [driver if w == "{driver}" else mode if w == "{mode}" else w for w in sub(cmd).split()]
    envd = dict(os.environ, **dict(kv.split("=", 1) for kv in sub(env).split()))
    return argv, envd


# --- workload --------------------------------------------------------------------------------

ASCII_LIT, ASCII_FILL = "abcde", "abcdefghijklmnopqrstuvwxyz0123456789 _-.,"
UNI_LIT = ["é", "ß", "σ", "ж", "中", "a", "b", "😀"]
UNI_FILL = list("abcdefghij 0123_") + list("éèàüßσςΣжЖ中文日本ął") + ["😀", "🎉"]
DIGITS, WORD, SPACE = "0123456789", "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_", " \t\n"


class Gen:
    """Pattern ASTs: ('lit', c) ('any',) ('cls', chars, neg) ('rng', lo, hi) ('esc', d|w|s) ('bol',)
    ('eol',) ('wb',) ('cat', [..]) ('alt', [..]) ('grp', cap, x) ('rep', x, lo, hi, lazy)."""

    def __init__(self, rng, uni):
        self.r, self.uni = rng, uni
        self.lits = UNI_LIT if uni else list(ASCII_LIT)

    def atom(self):
        r = self.r.random()
        if r < 0.45: return ("lit", self.r.choice(self.lits))
        if r < 0.55: return ("any",)
        if r < 0.68: return ("cls", "".join(self.r.sample(self.lits, 2)), self.r.random() < 0.3)
        if r < 0.75: return ("rng", "a", "e") if not self.uni or self.r.random() < 0.5 else ("rng", "α", "ω")
        if r < 0.92: return ("esc", self.r.choice("dws"))
        return ("wb",)

    def node(self, d):
        if d <= 0: return self.atom()
        r = self.r.random()
        if r < 0.35: return ("cat", [self.node(d - 1) for _ in range(self.r.randint(2, 4))])
        if r < 0.5: return ("alt", [self.node(d - 1) for _ in range(self.r.randint(2, 3))])
        if r < 0.8:
            lo, hi = self.r.choice([(0, None), (1, None), (0, 1), (2, 4), (1, 3), (3, 3), (0, 5)])
            body = self.node(d - 1)
            if body[0] == "wb": body = ("lit", self.r.choice(self.lits))  # a bare quantified assertion is an error in many engines
            if body[0] in ("cat", "alt", "rep"): body = ("grp", self.r.random() < 0.4, body)
            return ("rep", body, lo, hi, self.r.random() < 0.25)
        if r < 0.9: return ("grp", self.r.random() < 0.5, self.node(d - 1))
        return self.atom()

    def pattern(self):
        n = ("cat", [self.node(self.r.randint(1, 3)) for _ in range(self.r.randint(1, 3))])
        if self.r.random() < 0.1: n = ("cat", [("bol",), n])
        if self.r.random() < 0.1: n = ("cat", [n, ("eol",)])
        return n


def show(n, top=True):
    k = n[0]
    if k == "lit": return n[1] if n[1] not in ".[]()*+?{}|^$\\/-" else "\\" + n[1]
    if k == "any": return "."
    if k == "cls": return "[" + ("^" if n[2] else "") + n[1] + "]"
    if k == "rng": return "[" + n[1] + "-" + n[2] + "]"
    if k == "esc": return "\\" + n[1]
    if k == "bol": return "^"
    if k == "eol": return "$"
    if k == "wb": return "\\b"
    if k == "cat": return "".join(show(x, False) if x[0] != "alt" else "(?:" + show(x, False) + ")" for x in n[1])
    if k == "alt": return "|".join(show(x, False) for x in n[1])
    if k == "grp": return ("(" if n[1] else "(?:") + show(n[2], False) + ")"
    if k == "rep":
        body = show(n[1], False)
        lo, hi = n[2], n[3]
        q = "*" if (lo, hi) == (0, None) else "+" if (lo, hi) == (1, None) else "?" if (lo, hi) == (0, 1) \
            else "{%d,}" % lo if hi is None else "{%d}" % lo if lo == hi else "{%d,%d}" % (lo, hi)
        return body + q + ("?" if n[4] else "")
    raise ValueError(k)


def sample(n, r, uni):
    """A string the pattern probably matches."""
    k = n[0]
    if k == "lit": return n[1]
    if k == "any": return r.choice(UNI_FILL if uni else ASCII_FILL.replace("\n", ""))
    if k == "cls": return r.choice(n[1]) if not n[2] else r.choice([c for c in (UNI_FILL if uni else ASCII_FILL) if c not in n[1]])
    if k == "rng": return chr(r.randint(ord(n[1]), ord(n[2])))
    if k == "esc": return r.choice({"d": DIGITS, "w": WORD, "s": " "}[n[1]])
    if k in ("bol", "eol", "wb"): return ""
    if k == "cat": return "".join(sample(x, r, uni) for x in n[1])
    if k == "alt": return sample(r.choice(n[1]), r, uni)
    if k == "grp": return sample(n[2], r, uni)
    if k == "rep": return "".join(sample(n[1], r, uni) for _ in range(r.randint(n[2], n[3] if n[3] is not None else n[2] + 3)))
    raise ValueError(k)


def workload(n_pat, seed):
    cases = []
    for uni in (False, True):
        r = random.Random(seed * 2 + uni)
        g = Gen(r, uni)
        fill = UNI_FILL if uni else list(ASCII_FILL)
        for pi in range(n_pat):
            ast = g.pattern()
            pat = show(ast)
            flags = ("i" if r.random() < 0.2 else "") + ("u" if uni else "")
            core = sample(ast, r, uni)
            for bname, size, reps in BINS:
                def filler(k): return "".join(r.choice(fill) for _ in range(max(0, k)))
                left = r.randint(0, max(0, size - len(core)))
                a = filler(left) + core + filler(size - len(core) - left)
                shuffled = "".join(r.sample(core, len(core)))
                left = r.randint(0, max(0, size - len(core)))
                rr = filler(left) + shuffled + filler(size - len(core) - left)
                cases.append({"id": len(cases), "set": "unicode" if uni else "ascii", "bin": bname, "size": size,
                              "pattern": pat, "flags": flags, "reps": reps, "a": a, "r": rr, "pid": pi})
    return cases


# --- running ---------------------------------------------------------------------------------

class Host:
    def __init__(self, name, target, mode):
        self.argv, self.env = command(name, target, mode)
        self.p = None

    def start(self, timeout=120):
        self.p = subprocess.Popen(self.argv, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                  env=self.env, text=True, encoding="utf-8", bufsize=1)
        if not self.readline(timeout, want_ready=True): raise RuntimeError("no ready line")

    def readline(self, timeout, want_ready=False):
        end = time.time() + timeout
        while True:
            left = end - time.time()
            if left <= 0: return None
            r, _, _ = select.select([self.p.stdout], [], [], left)
            if not r: return None
            line = self.p.stdout.readline()
            if not line: return None
            if want_ready and line.startswith("ready"): return line
            if not want_ready and line[:1].isdigit(): return line

    def kill(self):
        if self.p:
            try: self.p.kill(); self.p.wait(5)
            except Exception: pass
        self.p = None

    def case(self, seq, c, timeout):
        req = json.dumps([seq, [[c["flags"] + "#" + str(c["reps"]), c["a"], c["r"], c["pattern"]]]], ensure_ascii=True, separators=(",", ":"))
        try:
            self.p.stdin.write(req + "\n"); self.p.stdin.flush()
        except (BrokenPipeError, OSError):
            return None
        line = self.readline(timeout)
        if line is None: return None
        parts = line.split()
        return parts[1] if len(parts) > 1 else None


def parse(h, reps):
    if h is None: return {"status": "timeout"}
    if h.startswith("fe"): return {"status": {"04": "compile_error", "08": "runtime_error", "40": "unsupported"}.get(h[2:4], "error")}
    if len(h) < 38: return {"status": "error"}
    return {"status": "ok", "bits": int(h[0:2], 16), "compile_ns": int(h[2:14], 16),
            "a_ns": int(h[14:26], 16) / reps, "r_ns": int(h[26:38], 16) / reps}


def run_engine(name, target, mode, cases, out, timeout):
    path = os.path.join(out, f"{name}.json")
    if os.path.exists(path): print(f"{name}: done already"); return
    h = Host(name, target, mode or "bench")
    res, t0, restarts = {}, time.time(), 0
    try: h.start()
    except Exception as e:
        print(f"{name}: failed to start ({e})"); json.dump({"engine": name, "error": str(e)}, open(path, "w")); return
    for c in cases:
        if h.p is None:
            try: h.start(); restarts += 1
            except Exception: res[c["id"]] = {"status": "start_failed"}; continue
        raw = h.case(c["id"], c, timeout)
        r = parse(raw, c["reps"])
        if r["status"] == "timeout" or raw is None: h.kill()
        elif r["status"] == "ok":
            # Coarse clocks (ms in Boa, XS, Hermes) and fast searches: rerun with more repetitions
            # until each timed loop takes at least MIN_LOOP_NS.
            total = min(r["a_ns"], r["r_ns"]) * c["reps"]
            if total < MIN_LOOP_NS:
                reps = min(c["reps"] * 200, max(c["reps"] * 2, int(c["reps"] * MIN_LOOP_NS / max(total, MIN_LOOP_NS / 200))))
                c2 = dict(c, reps=reps)
                raw2 = h.case(c["id"], c2, timeout)
                r2 = parse(raw2, reps)
                if r2["status"] == "ok": r2["compile_ns"] = r["compile_ns"]; r2["reps"] = reps; r = r2
                elif raw2 is None: h.kill()
        res[c["id"]] = r
    h.kill()
    ok = sum(1 for r in res.values() if r["status"] == "ok")
    print(f"{name}: {ok}/{len(cases)} ok, {restarts} restarts, {time.time() - t0:.0f}s", flush=True)
    json.dump({"engine": name, "target": target, "results": res}, open(path, "w"))


# --- report ----------------------------------------------------------------------------------

# Open ledger bugs (README) that affect each engine, by ID prefix (legacy and IRX- IDs). Shared
# engines inherit their library's bugs (PHP and Erlang embed PCRE2; SpiderMonkey shares
# Irregexp's IRX-V8-5; PCRE1 shares IRX-PCRE2-4, counted as one; Onigmo shares IRX-ONIG-1 but not
# IRX-ONIG-2, which is in Oniguruma's Python syntax).
LEDGER = {
    "resharp": ["IRX-RESHARP", "RESHARP"], "fancy-regex": ["IRX-FANCY"],
    "pcre2": ["IRX-PCRE2"], "pcre2-jit": ["IRX-PCRE2"], "php-pcre2": ["IRX-PCRE2"], "erlang-re": ["IRX-PCRE2"],
    "pcre1": [("IRX-PCRE2-4",)], "pcre1-jit": [("IRX-PCRE2-4",)],
    "oniguruma": ["IRX-ONIG"], "ruby-onigmo": [("IRX-ONIG-1",), "IRX-RUBY", "RUBY"],
    "re2": ["IRX-RE2"], "re2j": ["IRX-RE2J"], "icu-c": ["IRX-ICU", "ICU"], "icu": ["IRX-ICU", "ICU"],
    "vectorscan": ["IRX-HS", "HS"], "llvm-regex": ["IRX-LLVM"], "libc-regex": ["IRX-LIBC"],
    "cpp-regex": ["IRX-LIBCXX"], "boost-regex": ["IRX-BOOST"],
    "v8": ["IRX-V8", "V8"], "v8-linear": ["IRX-V8", "V8"], "spidermonkey": [("IRX-V8-5",)],
    "jsc": ["IRX-JSC"], "bun": ["JSC"], "quickjs": ["IRX-QJS"], "graaljs": ["IRX-GRAAL"],
    "boa": ["IRX-BOA"], "xs": ["IRX-XS"], "hermes": ["IRX-HERMES"],
    "perl": ["IRX-PERL", "PERL"], "tcl": ["IRX-TCL"], "java": ["IRX-JAVA", "JAVA"],
    "dotnet-interp": ["IRX-DOTNET", "DOTNET"], "dotnet-compiled": ["IRX-DOTNET", "DOTNET"], "dotnet-nonbacktracking": ["IRX-DOTNET", "DOTNET"],
    "swift-regex": ["IRX-SWIFT", "SWIFT", "SWIFT-PERF"], "racket": ["IRX-RACKET", "RACKET"],
    "emacs": ["IRX-EMACS"], "nim-regex": ["IRX-NIM", "NIM"],
    "python-re": ["IRX-PYRE"], "python-regex": ["IRX-PYREGEX"],
    "regex-lite": ["IRX-RLITE"],
}


def ledger_rows():
    rows = []
    for l in open(os.path.join(ROOT, "README.md")).read().splitlines():
        m = re.match(r"^\| \[?((?:IRX-)?[A-Z0-9-]+?)-(\d+)\]?", l)
        if not m: continue
        cols = [x.strip() for x in l.split("|")]
        st = cols[3].lower()
        rows.append((m.group(1), m.group(1) + "-" + m.group(2), st.startswith("open") or st.startswith("related")))
    return rows


def open_bugs(name, rows):
    ids = set()
    for spec in LEDGER.get(name, []):
        for pre, full, is_open in rows:
            if is_open and (full in spec if isinstance(spec, tuple) else pre == spec): ids.add(full)
    return sorted(ids)


FEATURES = ["lookahead", "lookbehind", "backrefs", "atomic", "possessive", "unicode_props", "named_groups", "inline_flags",
            "lazy", "word_boundary", "grapheme", "unicode_classes", "full_case_fold", "extended_mode"]
FAST, FEATUREFUL = 2.5, 8
CORE_COVERAGE = 0.95
# Constructs a dialect generates only because the host rewrites them into something else (the
# POSIX, Emacs and Racket hosts turn (?<name>...) into a plain group; Vectorscan reports no
# captures at all): the engine itself lacks them.
HOST_TRANSLATED = {d: ["named_groups"] for d in ("gnu", "llvm", "libc", "emacs", "racket", "vectorscan")}
# Features the engine supports but its dialect stops generating because a known bug would drown
# other findings (see the dialect comments): they still count toward the feature score.
SUPPRESSED = {"dotnet": ["atomic"], "dotnet-compiled": ["atomic"], "boost": ["atomic", "possessive", "grapheme"], "pcre1": ["grapheme"]}
STRICT_META = {}


def features():
    """Per dialect, from `irx features` (the dialect knobs)."""
    irx = os.environ.get("IRX", os.path.join(ROOT, "zig-out", "bin", "irx"))
    out = subprocess.run([irx, "features"], capture_output=True, text=True).stdout
    return {d["dialect"]: d for d in (json.loads(l) for l in out.splitlines() if l.startswith("{"))}


def tier(correct, fast, featureful):
    k = int(bool(fast)) + int(bool(featureful))
    return ("B", "A", "S")[k] if correct else ("F", "D", "C")[k]


def gmean(xs): return math.exp(sum(math.log(x) for x in xs) / len(xs)) if xs else None


def report(out):
    cases = json.load(open(os.path.join(out, "workload.json")))
    data = {}
    for name, *_ in ENGINES:
        p = os.path.join(out, f"{name}.json")
        if os.path.exists(p):
            d = json.load(open(p))
            if "results" in d: data[name] = {int(k): v for k, v in d["results"].items()}
    ref = data["rust-regex"]
    # One row per timed input: (case, which subject), labelled by Rust's outcome.
    inputs = []
    for c in cases:
        rr = ref.get(c["id"])
        if not rr or rr["status"] != "ok": continue
        for k, key in ((0, "a_ns"), (1, "r_ns")):
            inputs.append((c, key, "accept" if rr["bits"] >> k & 1 else "reject", rr[key]))
    summary = {}
    for name in data:
        d = data[name]
        rows = []
        for c, key, outcome, ref_ns in inputs:
            e = d.get(c["id"])
            if e and e["status"] == "ok" and ref_ns > 0 and e[key] > 0:
                rows.append((c, outcome, e[key] / ref_ns))
        statuses = {}
        for c in cases:
            s = d.get(c["id"], {"status": "missing"})["status"]
            statuses[s] = statuses.get(s, 0) + 1
        def g(f): v = [x for c, o, x in rows if f(c, o)]; return {"geo": gmean(v), "n": len(v)}
        comp = [d[c["id"]]["compile_ns"] for c in cases if c["bin"] == "tiny" and d.get(c["id"], {}).get("status") == "ok"]
        summary[name] = {
            "overall": g(lambda c, o: True),
            "by_set": {s: g(lambda c, o, s=s: c["set"] == s) for s in ("ascii", "unicode")},
            "by_outcome": {o2: g(lambda c, o, o2=o2: o == o2) for o2 in ("accept", "reject")},
            "by_bin": {b: g(lambda c, o, b=b: c["bin"] == b) for b, _, _ in BINS},
            "by_set_bin": {f"{s}/{b}": g(lambda c, o, s=s, b=b: c["set"] == s and c["bin"] == b) for s in ("ascii", "unicode") for b, _, _ in BINS},
            # The full cross: set x outcome x size.
            "cross": {f"{s}/{o2}/{b}": g(lambda c, o, s=s, o2=o2, b=b: c["set"] == s and o == o2 and c["bin"] == b)
                      for s in ("ascii", "unicode") for o2 in ("accept", "reject") for b, _, _ in BINS},
            "compile_median_ns": sorted(comp)[len(comp) // 2] if comp else None,
            "statuses": statuses, "coverage": statuses.get("ok", 0) / len(cases),
        }
    # Strict comparability: geometric means over inputs that a whole group of engines ran.
    # "core": every engine with at least CORE_COVERAGE of the cases; "all": every engine.
    def ran(name):
        d = data[name]
        return {(c["id"], key) for c, key, _, ref_ns in inputs
                if (e := d.get(c["id"])) and e["status"] == "ok" and ref_ns > 0 and e[key] > 0}
    ran_by = {n: ran(n) for n in summary}
    core = [n for n in summary if summary[n]["coverage"] >= CORE_COVERAGE]
    shared_core = set.intersection(*(ran_by[n] for n in core)) if core else set()
    shared_all = set.intersection(*ran_by.values()) if ran_by else set()
    by_key = {(c["id"], key): (c, outcome, ref_ns) for c, key, outcome, ref_ns in inputs}
    def strict(name, keys):
        d = data[name]
        rows = [(by_key[k][0], by_key[k][1], d[k[0]][k[1]] / by_key[k][2]) for k in keys]
        def g(f): v = [x for c, o, x in rows if f(c, o)]; return {"geo": gmean(v), "n": len(v)}
        return {"overall": g(lambda c, o: True),
                "by_set": {s: g(lambda c, o, s=s: c["set"] == s) for s in ("ascii", "unicode")},
                "by_outcome": {o2: g(lambda c, o, o2=o2: o == o2) for o2 in ("accept", "reject")},
                "by_bin": {b: g(lambda c, o, b=b: c["bin"] == b) for b, _, _ in BINS},
                "cross": {f"{s}/{o2}/{b}": g(lambda c, o, s=s, o2=o2, b=b: c["set"] == s and o == o2 and c["bin"] == b)
                          for s in ("ascii", "unicode") for o2 in ("accept", "reject") for b, _, _ in BINS}}
    for n in summary:
        summary[n]["strict_all"] = strict(n, shared_all)
        summary[n]["core"] = n in core
        if n in core: summary[n]["strict_core"] = strict(n, shared_core)
        # The ranking speed: the core set for core engines, the all-engine set otherwise.
        summary[n]["rank"] = (summary[n]["strict_core"] if n in core else summary[n]["strict_all"])
    STRICT_META.update({"core_engines": len(core), "core_inputs": len(shared_core), "all_inputs": len(shared_all),
                        "total_inputs": len(inputs), "core_coverage": CORE_COVERAGE})
    rows_l, feats = ledger_rows(), features()
    for name in summary:
        tgt = dict((e[0], e[1]) for e in ENGINES)[name]
        dia = re.search(r'^dialect = "(.*?)"', open(os.path.join(ROOT, "targets", tgt, "target.toml")).read(), re.M).group(1)
        f = feats.get(dia, {})
        have = [k for k in FEATURES if (f.get(k) or k in SUPPRESSED.get(dia, [])) and k not in HOST_TRANSLATED.get(dia, [])]
        bugs = open_bugs(name, rows_l)
        geo = summary[name]["rank"]["overall"]["geo"]
        summary[name].update({"dialect": dia, "features": have, "feature_count": len(have), "open_bugs": bugs,
                              "fast": bool(geo and geo <= FAST), "featureful": len(have) >= FEATUREFUL,
                              "family": dict((e[0], e[2]) for e in ENGINES)[name]})
        summary[name]["tier"] = tier(not bugs, summary[name]["fast"], summary[name]["featureful"])
    json.dump(summary, open(os.path.join(out, "summary.json"), "w"), indent=1)
    json.dump(STRICT_META, open(os.path.join(out, "strict.json"), "w"))
    print(f"core set: {STRICT_META['core_engines']} engines, {STRICT_META['core_inputs']} of {STRICT_META['total_inputs']} inputs; all-engine set: {STRICT_META['all_inputs']} inputs")
    order = sorted(summary, key=lambda n: summary[n]["rank"]["overall"]["geo"] or 1e9)
    fmt = lambda x: f"{x:7.2f}" if x else "     - "
    print(f"{'engine':24} {'tier':>4} {'bugs':>4} {'feat':>4} {'overall':>7} {'ascii':>7} {'uni':>7} {'accept':>7} {'reject':>7} {'tiny':>7} {'small':>7} {'medium':>7} {'large':>7}  cover")
    for n in order:
        s = summary[n]
        print(f"{n:24} {s['tier']:>4} {len(s['open_bugs']):>4} {s['feature_count']:>4} {fmt(s['rank']['overall']['geo'])} {fmt(s['by_set']['ascii']['geo'])} {fmt(s['by_set']['unicode']['geo'])} "
              f"{fmt(s['by_outcome']['accept']['geo'])} {fmt(s['by_outcome']['reject']['geo'])} "
              + " ".join(fmt(s['by_bin'][b]['geo']) for b, _, _ in BINS) + f"  {s['coverage']:.0%}")


LABELS = {
    "rust-regex": "Rust regex", "regex-lite": "regex-lite", "ra-pikevm": "regex-automata PikeVM", "ra-backtrack": "regex-automata backtrack",
    "ra-hybrid": "regex-automata lazy DFA", "ra-dfa": "regex-automata dense DFA", "fancy-regex": "fancy-regex", "resharp": "RE#",
    "pcre2": "PCRE2", "pcre2-jit": "PCRE2 JIT", "pcre1": "PCRE1", "pcre1-jit": "PCRE1 JIT", "oniguruma": "Oniguruma", "re2": "RE2",
    "icu-c": "ICU4C", "vectorscan": "Vectorscan", "llvm-regex": "LLVM Regex", "libc-regex": "macOS libc regex", "gnu-regex": "GNU regex",
    "minrx": "MinRX", "cpp-regex": "libc++ std::regex", "boost-regex": "Boost.Regex", "v8": "V8 (Irregexp)", "v8-linear": "V8 linear engine",
    "spidermonkey": "SpiderMonkey", "jsc": "JSC (macOS 27)", "bun": "JSC (Bun)", "quickjs": "QuickJS", "graaljs": "GraalJS (TRegex)",
    "boa": "Boa", "xs": "XS", "hermes": "Hermes", "python-re": "Python re", "python-regex": "Python regex", "ruby-onigmo": "Ruby (Onigmo)",
    "perl": "Perl", "php-pcre2": "PHP preg", "tcl": "Tcl", "java": "Java", "re2j": "re2j", "dotnet-interp": ".NET", "dotnet-compiled": ".NET Compiled",
    "dotnet-nonbacktracking": ".NET NonBacktracking", "go-regexp": "Go regexp", "swift-regex": "Swift Regex", "icu": "ICU (NSRegularExpression)",
    "erlang-re": "Erlang re", "racket": "Racket", "emacs": "Emacs", "nim-regex": "nim-regex",
}
FEATURE_LABELS = {"lookahead": "look→", "lookbehind": "←look", "backrefs": "\\1", "atomic": "(?>)", "possessive": "*+", "unicode_props": "\\p",
                  "named_groups": "(?<n>)", "inline_flags": "(?i:)", "lazy": "*?", "word_boundary": "\\b", "grapheme": "\\X",
                  "unicode_classes": "Uni", "full_case_fold": "ß=ss", "extended_mode": "(?x)"}
SCALE = ["rust-regex", "pcre2-jit", "bun", "v8", "re2", "go-regexp", "python-re", "java"]


def page(out, dest, extras=None, strict_only=False, title=None, no_bug_ids=False, concise=False):
    summary = json.load(open(os.path.join(out, "summary.json")))
    cases = json.load(open(os.path.join(out, "workload.json")))
    scale = {}
    for name in SCALE:
        p = os.path.join(out, f"{name}.json")
        if not os.path.exists(p): continue
        d = json.load(open(p)).get("results", {})
        scale[name] = {}
        for b, _, _ in BINS:
            v = sorted(x for c in cases if c["bin"] == b and c["set"] == "ascii" and d.get(str(c["id"]), {}).get("status") == "ok"
                       for x in (d[str(c["id"])]["a_ns"], d[str(c["id"])]["r_ns"]) if x > 0)
            if v: scale[name][b] = v[len(v) // 2]
    strict_meta = json.load(open(os.path.join(out, "strict.json")))
    if no_bug_ids:  # counts only: the ledger IDs stay out of the page source
        for v in summary.values(): v["open_bugs"] = ["open"] * len(v["open_bugs"])
    meta = {"concise": concise, "no_bug_ids": no_bug_ids, "strict_only": strict_only, "strict": strict_meta, "labels": LABELS, "fast": FAST, "featureful": FEATUREFUL, "features": FEATURES, "feature_labels": FEATURE_LABELS,
            "patterns": len(cases) // len(BINS) // 2, "inputs": len(cases) * 2, "bins": [[b, n] for b, n, _ in BINS],
            "scale_engines": SCALE, "ledger_open": sum(1 for _, _, o in ledger_rows() if o), "date": time.strftime("%Y-%m-%d")}
    html = open(os.path.join(ROOT, "tools", "shootout2.html")).read().replace("/*DATA*/null", json.dumps({"summary": summary, "meta": meta, "scale": scale,
                                                                                                 "extras": json.load(open(extras)) if extras else {}}))
    if title:
        html = html.replace("<title>Regex Shootout 2</title>", f"<title>{title}</title>").replace("<h1>Regex Shootout 2</h1>", f"<h1>{title}</h1>")
    open(dest, "w").write(html)
    print("wrote", dest)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["run", "report", "smoke", "page"])
    ap.add_argument("--html", default=None)
    ap.add_argument("--concise", action="store_true", help="page: short copy, just enough to read the charts")
    ap.add_argument("--title", default=None, help="page: title and headline")
    ap.add_argument("--no-bug-ids", action="store_true", help="page: bug counts only, no ledger IDs")
    ap.add_argument("--strict-only", action="store_true", help="page: show only the strict view, without the switch")
    ap.add_argument("--extras", default=None, help="page: JSON of untiered rows shown for comparison only (engines irx does not fuzz)")
    ap.add_argument("--engines", default=None)
    ap.add_argument("--patterns", type=int, default=150)
    ap.add_argument("--seed", type=int, default=2)
    ap.add_argument("--timeout", type=float, default=10)
    ap.add_argument("--out", default=os.path.join(ROOT, "bench-out"))
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    wl = os.path.join(a.out, "workload.json")
    if not os.path.exists(wl): json.dump(workload(a.patterns, a.seed), open(wl, "w"))
    cases = json.load(open(wl))
    sel = [e for e in ENGINES if not a.engines or e[0] in a.engines.split(",")]
    if a.cmd == "smoke":
        for name, target, _, mode in sel:
            h = Host(name, target, mode or "bench")
            try:
                h.start(60); raw = h.case(1, cases[0], 30); print(f"{name:24} {parse(raw, cases[0]['reps'])}")
            except Exception as e: print(f"{name:24} FAILED {e}")
            h.kill()
    elif a.cmd == "run":
        for name, target, _, mode in sel: run_engine(name, target, mode, cases, a.out, a.timeout)
    elif a.cmd == "page":
        page(a.out, a.html or os.path.join(a.out, "shootout2.html"), a.extras, a.strict_only, a.title, a.no_bug_ids, a.concise)
    else:
        report(a.out)


if __name__ == "__main__":
    main()
