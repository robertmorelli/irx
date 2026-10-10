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

def limit():
    resource.setrlimit(resource.RLIMIT_CPU, (CPU_LIMIT_S, CPU_LIMIT_S + 1))

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
                f.write("var __IRX_MODE = " + json.dumps(mode) + ";\n")
                f.write(core)
            p = subprocess.run([shell, *extra, path], stdout=subprocess.PIPE, stderr=subprocess.PIPE, preexec_fn=limit)
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
