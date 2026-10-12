#!/usr/bin/env python3
"""Run irx campaigns for targets/<name>/target.toml and record results.

usage: tools/irx_target.py NAME... | --all  [--duration S] [--seed N] [--jobs J]
                                           [--label L] [--selfcheck-only] [--no-readme] [--no-selfcheck]
                                           [--long [--long-lengths "64, 256, 1000, 4096"]]

`--all` skips targets whose [target] section sets `campaign = false`.
`--long` runs a long-input campaign instead: only the long mode, with a pumped long pair for
every case (label prefix `long-`).
Each run writes findings/<label>-<name>/ (with the merged campaign.toml) and, unless
--no-readme, refreshes the "<name> <label> results" block in targets/<name>/README.md.
Placeholders in `command`: {root} (repo), {home}, {driver}, {mode} (filled by irx).
"""
import argparse, os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def target_meta(name):
    text = open(os.path.join(ROOT, "targets", name, "target.toml")).read()
    sec = re.search(r"^\[target\]\n(.*?)(?=^\[|\Z)", text, re.S | re.M).group(1)
    meta = {}
    for line in sec.splitlines():
        m = re.match(r'\s*(\w+)\s*=\s*("([^"]*)"|true|false)', line)
        if m: meta[m.group(1)] = m.group(3) if m.group(3) is not None else (m.group(2) == "true")
    return meta, text

def apply_block(readme, block):
    name = re.search(r"<!-- BEGIN (.*?) -->", block).group(1)
    s = open(readme).read() if os.path.exists(readme) else ""
    pat = re.compile(r"<!-- BEGIN " + re.escape(name) + r" -->.*?<!-- END " + re.escape(name) + r" -->\n?", re.S)
    s = pat.sub(lambda m: block, s) if pat.search(s) else s.rstrip("\n") + "\n\n" + block
    open(readme, "w").write(s)

def run(name, a):
    meta, text = target_meta(name)
    sub = lambda c: c.replace("{root}", ROOT).replace("{home}", os.path.expanduser("~"))
    cmd = sub(meta["command"])
    label = a.label or ("selfcheck" if a.selfcheck_only else f"{a.duration // 60}m" if a.duration % 60 == 0 else f"{a.duration}s")
    if a.long and not a.label: label = "long-" + label
    out = os.path.join(ROOT, "findings", f"{label}-{name}")
    subprocess.run(["rm", "-rf", out]); os.makedirs(out)
    cfg = os.path.join(out, "campaign.toml")
    # --long: a long-input campaign (only the long modes, every case pumped; src/long.zig). A later
    # [long] section overrides these keys and keeps the target's own (e.g. deadline_ms_per_case).
    if a.long: text += f"\n[long]\nonly = true\nfraction = 1.0\nlengths = [{a.long_lengths}]\n"
    open(cfg, "w").write(open(os.path.join(ROOT, "weights.toml")).read() + "\n" + text)
    irx = [os.path.join(ROOT, "zig-out/bin/irx")]
    if a.selfcheck_only: irx.append("selfcheck")
    kind = meta.get("kind", "shell")
    irx += {"d8": ["--d8", cmd], "perl": ["--perl", cmd]}.get(kind, ["--shell", cmd])
    irx += ["--dialect", meta.get("dialect", "es"), "--config", cfg, "--out", out]
    # modes / optional_modes ([target]): override the engine's default mode list (d8: interp,
    # native, tierup) or add optional ones (d8: linear, noopt, nopeephole, fallback0).
    if meta.get("modes"): irx += ["--modes", meta["modes"]]
    if meta.get("optional_modes"): irx += ["--optional-modes", meta["optional_modes"]]
    if not a.selfcheck_only:
        irx += ["--jobs", str(a.jobs), "--seed", str(a.seed), "--duration", str(a.duration)]
        if not meta.get("selfcheck", True) or a.no_selfcheck: irx.append("--no-selfcheck")
    # env ([target]): "NAME=value ..." set for irx and the engine processes it starts.
    env = dict(os.environ, **dict(kv.split("=", 1) for kv in meta.get("env", "").split()))
    with open(out + ".log", "w") as log:
        rc = subprocess.run(irx, stdout=log, stderr=subprocess.STDOUT, env=env).returncode
    print(f"{name}: rc={rc}", flush=True)
    if not a.no_readme and not a.selfcheck_only:
        block = subprocess.run([sys.executable, os.path.join(ROOT, "tools/summarize.py"), out, name, meta.get("title", name), label],
                               capture_output=True, text=True).stdout
        readme = os.path.join(ROOT, "targets", name, "README.md")
        if not os.path.exists(readme): open(readme, "w").write(f"# {meta.get('title', name)}\n\nSee [`target.toml`](target.toml) for how irx drives this engine.\n")
        apply_block(readme, block)
    return rc

def main():
    p = argparse.ArgumentParser()
    p.add_argument("names", nargs="*"); p.add_argument("--all", action="store_true")
    p.add_argument("--duration", type=int, default=60); p.add_argument("--seed", type=int, default=2026)
    p.add_argument("--jobs", type=int, default=8); p.add_argument("--label")
    p.add_argument("--selfcheck-only", action="store_true"); p.add_argument("--no-readme", action="store_true")
    p.add_argument("--no-selfcheck", action="store_true")
    p.add_argument("--long", action="store_true", help="long-input campaign: only the long mode, every case gets a pumped long pair")
    p.add_argument("--long-lengths", default="64, 256, 1000, 4096", help="target lengths for --long (symbols)")
    a = p.parse_args()
    # --all skips targets marked `campaign = false` (they can still be run by name).
    names = [n for n in sorted(os.listdir(os.path.join(ROOT, "targets"))) if target_meta(n)[0].get("campaign", True)] if a.all else a.names
    if not names: p.error("give target names or --all")
    rcs = [run(n, a) for n in names]
    sys.exit(0 if all(r == 0 for r in rcs) else 1)

main()
