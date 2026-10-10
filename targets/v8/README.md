# V8 15.5 (d8)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py v8`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN v8 1m results -->
### V8 15.5 (d8): 1-minute smoke campaign

* 411,264 patterns, 6 tables, 56 distinct findings; self-check 1,628,352 probes, 0 mismatches, 0 engine failures
* findings by kind: 56 timeout (batch)

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END v8 1m results -->
