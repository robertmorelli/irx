# Vectorscan (Hyperscan)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py vectorscan`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN vectorscan 1m results -->
### vectorscan: 1-minute smoke campaign

* 59,392 patterns, 2 tables, 232 distinct findings; self-check 281,792 probes, 57,728 mismatches, 0 engine failures
* findings by kind: 232 timeout (batch), 200 syntax_error (selfcheck)

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END vectorscan 1m results -->

<!-- BEGIN vectorscan 10m results -->
### Vectorscan (Hyperscan): 10m campaign

* 19,264 patterns, 2 tables, 22 distinct findings; self-check 272,528 probes, 0 mismatches, 0 engine failures
* findings by kind: 22 timeout (batch)

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END vectorscan 10m results -->

<!-- BEGIN vectorscan 10m triage -->
### vectorscan: 10-minute campaign triage

* Clean but thin: 19 K cases (slow compiles), 0 wrong results, self-check clean. The 22 timeouts did not reproduce.
<!-- END vectorscan 10m triage -->

<!-- BEGIN vectorscan 5m results -->
### Vectorscan (Hyperscan): 5m campaign

* 9,088 patterns, 2 tables, 0 distinct findings; self-check 272,528 probes, 0 mismatches, 0 engine failures

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END vectorscan 5m results -->
