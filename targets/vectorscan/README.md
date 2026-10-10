# Vectorscan (Hyperscan)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py vectorscan`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN vectorscan 1m results -->
### vectorscan: 1-minute smoke campaign

* 59,392 patterns, 2 tables, 232 distinct findings; self-check 281,792 probes, 57,728 mismatches, 0 engine failures
* findings by kind: 232 timeout (batch), 200 syntax_error (selfcheck)

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END vectorscan 1m results -->
