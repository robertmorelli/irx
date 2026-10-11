#!/usr/bin/env python3
"""Sampled triage of a finished campaign: minimize a few findings from every signature group.

usage: tools/irx_triage.py NAME --label L [--per-group K] [--max N] [--jobs J] [--timeout S]
                           [--irx PATH] [--report-only]

Campaigns minimize only what their triage queue keeps up with; big known bugs then hide rare
ones. This groups the not-yet-triaged findings in findings/<label>-<name>/ by a cheap
signature (kind, mode, flags, and the constructs the pattern uses), picks the K smallest of
each group (at most N overall), runs `irx triage --ids` on them at low priority, and prints
every minimized shape of the run, grouped, rarest first. Timeouts are left out (they need
batch bisection and are mostly engine slowness).
"""
import argparse, collections, json, os, re, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
FEATURES = ["look_ahead", "neg_look_ahead", "look_behind", "neg_look_behind", "group_cap", "group_named",
            "star", "plus", "opt", "range", "open", "exact", "caret", "dollar", "wordb", "nwordb", "empty",
            "vset", "dot", "esc", "cls"]


def target_meta(name):
    text = open(os.path.join(ROOT, "targets", name, "target.toml")).read()
    sec = re.search(r"^\[target\]\n(.*?)(?=^\[|\Z)", text, re.S | re.M).group(1)
    meta = {}
    for line in sec.splitlines():
        m = re.match(r'\s*(\w+)\s*=\s*("([^"]*)"|true|false)', line)
        if m: meta[m.group(1)] = m.group(3) if m.group(3) is not None else (m.group(2) == "true")
    return meta


def field(text, key):
    m = re.search(rf"^{key}=(.*)$", text, re.M)
    return m.group(1) if m else ""


def signature(case):
    """Coarse: kind, mode family, flag class, and which risky constructs appear (a few hundred
    groups per run, so rare combinations still get sampled)."""
    ast = field(case, "ast")
    toks = set(re.findall(r"[a-z_]+", ast))
    feats = []
    if toks & {"look_ahead", "neg_look_ahead"}: feats.append("lookahead")
    if toks & {"look_behind", "neg_look_behind"}: feats.append("lookbehind")
    if toks & {"group_cap", "group_named"}: feats.append("capture")
    if re.search(r"\(quant \w+ \d+ \d+ 1 ", ast): feats.append("lazy")
    if toks & {"range", "open", "exact"}: feats.append("counted")
    if re.search(r"\(quant [^()]*\((?:[^()]|\([^()]*\))*\(quant", ast): feats.append("nested")
    if toks & {"caret", "dollar"}: feats.append("anchor")
    if toks & {"wordb", "nwordb"}: feats.append("wordb")
    if "empty" in toks: feats.append("empty")
    if "vset" in toks: feats.append("vset")
    fl = field(case, "flags")
    fclass = ("v" if "v" in fl else "u" if "u" in fl else "-") + ("i" if "i" in fl else "") + ("m" if "m" in fl else "") + ("s" if "s" in fl else "")
    mode = field(case, "mode")
    return (field(case, "kind"), mode.split("-")[-1] if "-" in mode else "full", fclass, " ".join(feats))


def shapes(fdir):
    out = collections.Counter()
    for d in os.listdir(fdir):
        tj = os.path.join(fdir, d, "triage.json")
        if not os.path.exists(tj): continue
        try: t = json.load(open(tj))
        except Exception: continue
        m = t.get("minimized")
        if not m: continue
        det = t.get("span") or t.get("captures") or {}
        extra = "" if not det else f" A {det.get('expected_a')}->{det.get('observed_a')} R {det.get('expected_r')}->{det.get('observed_r')}"
        # Long modes ran on the long pair: show that, not the short pair.
        long = "long" in t.get("mode", "")
        sa, sr = (m.get("LA", ""), m.get("LR", "")) if long else (m["A"], m["R"])
        out[(m["kind"], t.get("mode", ""), m["flags"], json.dumps(sa, ensure_ascii=False), json.dumps(sr, ensure_ascii=False), m["pattern"], m["observed_bits"] + extra)] += 1
    return out


def main():
    p = argparse.ArgumentParser()
    p.add_argument("name"); p.add_argument("--label", required=True)
    p.add_argument("--per-group", type=int, default=2); p.add_argument("--max", type=int, default=300)
    p.add_argument("--jobs", type=int, default=2); p.add_argument("--timeout", type=int, default=1500)
    p.add_argument("--irx", default=os.path.join(ROOT, "zig-out/bin/irx")); p.add_argument("--report-only", action="store_true")
    a = p.parse_args()
    out = os.path.join(ROOT, "findings", f"{a.label}-{a.name}"); fdir = os.path.join(out, "findings")
    groups = collections.defaultdict(list); pending = 0
    for d in sorted(os.listdir(fdir)):
        cf = os.path.join(fdir, d, "case.irx")
        if not os.path.exists(cf) or os.path.exists(os.path.join(fdir, d, "triage.json")): continue
        c = open(cf).read()
        if field(c, "kind") in ("timeout", "selfcheck_mismatch"): continue
        pending += 1
        groups[signature(c)].append((int(field(c, "size") or 0), int(d)))
    picked = []
    for sig, items in sorted(groups.items(), key=lambda kv: len(kv[1])):  # rare groups first
        picked += [i for _, i in sorted(items)[:a.per_group]]
    picked = picked[:a.max]
    print(f"{a.name}: {pending} untriaged findings in {len(groups)} signature groups; triaging {len(picked)}", flush=True)
    if picked and not a.report_only:
        meta = target_meta(a.name)
        cmd = meta["command"].replace("{root}", ROOT).replace("{home}", os.path.expanduser("~"))
        kind = meta.get("kind", "shell")
        engine = {"d8": ["--d8", cmd], "perl": ["--perl", cmd]}.get(kind, ["--shell", cmd])
        with tempfile.NamedTemporaryFile("w", suffix=".ids", delete=False) as f:
            f.write("\n".join(map(str, picked))); ids = f.name
        irx = ["nice", "-n", "10", a.irx, "triage", *engine, "--dialect", meta.get("dialect", "es"), "--out", out, "--ids", ids, "--jobs", str(a.jobs)]
        try: subprocess.run(irx, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=a.timeout)
        except subprocess.TimeoutExpired: print("  (triage stopped at the time limit)")
        os.unlink(ids)
    sh = shapes(fdir)
    print(f"  minimized shapes: {sum(sh.values())} findings, {len(sh)} distinct; rarest first:")
    for s, c in sorted(sh.items(), key=lambda kv: kv[1])[:60]:
        print("  ", c, *s, sep="  ")


main()
