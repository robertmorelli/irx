#!/usr/bin/env python3
"""irx bridge for JS shells without stdin (Hermes, XS, engine262, Boa, ...).

Usage: bridge.py SHELL DRIVER_JS MODE [shell args...]
Speaks the irx line protocol on stdin/stdout. For each request line it writes a
temporary script (one embedded batch + driver.js) and runs SHELL on it, relaying
the single response line. A shell killed by a signal makes the bridge die with
the same signal, so the harness records a crash. Each shell run gets a CPU-time
limit so a hang cannot outlive the harness's deadline by much.
"""
import json, os, resource, signal, subprocess, sys, tempfile

CPU_LIMIT_S = 20
WALL_LIMIT_S = float(os.environ.get("IRX_BRIDGE_WALL_S", "30"))
MEM_LIMIT = 4 << 30  # best effort; macOS may not enforce RLIMIT_DATA/AS

def limit():
    resource.setrlimit(resource.RLIMIT_CPU, (CPU_LIMIT_S, CPU_LIMIT_S + 1))
    for r in (resource.RLIMIT_DATA, resource.RLIMIT_AS):
        try:
            resource.setrlimit(r, (MEM_LIMIT, MEM_LIMIT))
        except (ValueError, OSError):
            pass

def main():
    shell, driver, mode, extra = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:]
    core = open(driver, encoding="utf-8").read()
    print(f"ready bridge:{os.path.basename(shell)} mode={mode}", flush=True)
    fd, path = tempfile.mkstemp(suffix=".js", prefix="irx-bridge-")
    os.close(fd)
    try:
        for line in sys.stdin:
            line = line.rstrip("\n")
            if not line:
                continue
            with open(path, "w", encoding="utf-8") as f:
                f.write("var __IRX_BATCH = " + json.dumps(line) + ";\n")
                # Also as an object literal: JSON is valid JS, and string literals accept lone
                # surrogate escapes even where JSON.parse wrongly rejects them (Boa).
                f.write("var __IRX_BATCH_OBJ = " + line + ";\n")
                f.write("var __IRX_MODE = " + json.dumps(mode) + ";\n")
                f.write(core)
            # The shell stays in the bridge's process group, so the harness's
            # group kill on timeout reaches it; the wall limit is a backstop.
            try:
                p = subprocess.run([shell, *extra, path], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   preexec_fn=limit, timeout=WALL_LIMIT_S)
            except subprocess.TimeoutExpired:
                sys.stderr.write("bridge: shell exceeded wall limit\n")
                sys.exit(1)
            sys.stderr.buffer.write(p.stderr[-65536:])
            if p.returncode < 0:  # killed by a signal: crash with the same signal
                sys.stderr.flush()
                signal.signal(-p.returncode, signal.SIG_DFL)
                os.kill(os.getpid(), -p.returncode)
            resp = [l for l in p.stdout.decode("utf-8", "replace").splitlines() if l and l[0].isdigit()]
            if not resp:
                sys.stderr.write(f"bridge: shell exited {p.returncode} without a response\n")
                sys.exit(1)
            print(resp[-1], flush=True)
    finally:
        os.unlink(path)

if __name__ == "__main__":
    main()
