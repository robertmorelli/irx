# V8 15.5 (d8)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py v8`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN v8 1m results -->
### V8 15.5 (d8): 1-minute smoke campaign

* 411,264 patterns, 6 tables, 56 distinct findings; self-check 1,628,352 probes, 0 mismatches, 0 engine failures
* findings by kind: 56 timeout (batch)

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END v8 1m results -->

<!-- BEGIN v8 10m results -->
### V8 15.5 (d8): 10m campaign

* 1,987,552 patterns, 21 tables, 1,219 distinct findings; self-check 1,628,352 probes, 0 mismatches, 0 engine failures
* findings by kind: 1,219 timeout (batch)

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END v8 10m results -->

<!-- BEGIN v8 10m triage -->
### v8: 10-minute campaign triage

* No wrong results and a clean self-check on d8 15.5 (2.0 M cases). The surrogate-pair family seen on Node/Deno
  did not appear, and IRX-V8-1…3 did not recur.
* 1,219 timeouts, none reproduced alone during triage; consistent with the load-induced timeouts on Bun, Deno and Node.
<!-- END v8 10m triage -->
