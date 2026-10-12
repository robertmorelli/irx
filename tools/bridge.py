#!/usr/bin/env python3
"""irx bridge for JS shells without stdin (Hermes, XS, engine262, Boa, ...).

Usage: bridge.py SHELL DRIVER_JS MODE [shell args...]
Speaks the irx line protocol on stdin/stdout. For each request line it writes a
temporary script (one embedded batch + driver.js) and runs SHELL on it, relaying
the single response line. A shell killed by a signal makes the bridge die with
the same signal, so the harness records a crash.

Hangs: each shell run has a wall-clock limit that scales with the number of cases.
When a run exceeds it, the batch is split in half and each half is retried; a single
case that still exceeds the limit is reported as unsupported (bits 0x40, or the
span/capture-mode equivalent) instead of costing the whole batch. Engines with
known infinite loops (Boa IRX-BOA-8, XS IRX-XS-7) or exponential blowups (Hermes
IRX-HERMES-2) keep running. The harness's batch deadline must cover the bisection
(targets that need it set a larger batch_deadline_base_ms and a smaller batch_size).
"""
import json, os, resource, signal, subprocess, sys, tempfile

CPU_LIMIT_S = 20
MEM_LIMIT = 4 << 30  # best effort; macOS may not enforce RLIMIT_DATA/AS
# Wall-clock limit for one shell run: BASE + PER_CASE * cases (seconds).
BASE_S = float(os.environ.get("IRX_BRIDGE_BASE_S", "0.5"))
PER_CASE_S = float(os.environ.get("IRX_BRIDGE_PER_CASE_S", "0.02"))
# Result hex digits per case and the "unsupported" marker for each driver mode.
# Long modes (lspan, lcapture) use 4 hex digits per position; "unsupported" is fffe + 0040.
WIDTH = {"span": 8, "capture": 56, "lspan": 16, "lcapture": 112, "ospan": 8}
SKIP = {"span": "fe400000", "ospan": "fe400000", "capture": "fe40" + "00" * 26, "lspan": "fffe0040" + "0" * 8, "lcapture": "fffe0040" + "0000" * 26}


def limit():
    resource.setrlimit(resource.RLIMIT_CPU, (CPU_LIMIT_S, CPU_LIMIT_S + 1))
    for r in (resource.RLIMIT_DATA, resource.RLIMIT_AS):
        try:
            resource.setrlimit(r, (MEM_LIMIT, MEM_LIMIT))
        except (ValueError, OSError):
            pass


class Bridge:
    def __init__(self, shell, driver, mode, extra):
        self.shell, self.mode, self.extra = shell, mode, extra
        self.core = open(driver, encoding="utf-8").read()
        self.width = WIDTH.get(mode, 2)
        self.skip = SKIP.get(mode, "40")
        fd, self.path = tempfile.mkstemp(suffix=".js", prefix="irx-bridge-")
        os.close(fd)

    def run(self, line, ncases):
        """Run one request line. Returns the result hex, or None on timeout."""
        with open(self.path, "w", encoding="utf-8") as f:
            # Concatenated short literals: XS rejects the whole script when one string literal's
            # source reaches 64K characters ("buffer overflow"; this was IRX-XS-3). 4096 characters
            # stay under that even when json.dumps escapes every one as a 12-character pair.
            parts = [json.dumps(line[i:i + 4096]) for i in range(0, len(line), 4096)] or ['""']
            f.write("var __IRX_BATCH = " + " +\n  ".join(parts) + ";\n")
            # Also as an object literal: JSON is valid JS, and string literals accept lone
            # surrogate escapes even where JSON.parse wrongly rejects them (Boa).
            f.write("var __IRX_BATCH_OBJ = " + line + ";\n")
            f.write("var __IRX_MODE = " + json.dumps(self.mode) + ";\n")
            f.write(self.core)
        # The shell stays in the bridge's process group, so the harness's group kill on
        # timeout reaches it.
        try:
            p = subprocess.run([self.shell, *self.extra, self.path], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               preexec_fn=limit, timeout=BASE_S + PER_CASE_S * ncases)
        except subprocess.TimeoutExpired:
            return None
        sys.stderr.buffer.write(p.stderr[-65536:])
        if p.returncode == -signal.SIGXCPU:  # CPU-time limit: a hang, not a crash
            return None
        if p.returncode < 0:  # killed by a signal: crash with the same signal
            sys.stderr.flush()
            signal.signal(-p.returncode, signal.SIG_DFL)
            os.kill(os.getpid(), -p.returncode)
        resp = [l for l in p.stdout.decode("utf-8", "replace").splitlines() if l and l[0].isdigit()]
        if not resp:
            sys.stderr.write(f"bridge: shell exited {p.returncode} without a response\n")
            sys.exit(1)
        return resp[-1].split(" ", 1)[1].strip()

    def solve(self, seq, cases):
        """Results for `cases`, splitting on timeouts down to single cases."""
        line = json.dumps([seq, cases], separators=(",", ":"))
        hexes = self.run(line, len(cases))
        if hexes is not None:
            return hexes
        if len(cases) == 1:
            sys.stderr.write("bridge: case exceeded the time limit; reported as unsupported\n")
            return self.skip
        mid = len(cases) // 2
        return self.solve(seq, cases[:mid]) + self.solve(seq, cases[mid:])

    def serve(self):
        print(f"ready bridge:{os.path.basename(self.shell)} mode={self.mode}", flush=True)
        try:
            for line in sys.stdin:
                line = line.rstrip("\n")
                if not line:
                    continue
                seq, cases = json.loads(line)
                hexes = self.run(line, len(cases))
                if hexes is None:
                    hexes = self.solve(seq, cases) if len(cases) > 1 else self.skip
                print(f"{seq} {hexes}", flush=True)
        finally:
            os.unlink(self.path)


if __name__ == "__main__":
    Bridge(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:]).serve()
