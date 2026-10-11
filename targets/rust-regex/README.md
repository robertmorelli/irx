# Rust regex

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py rust-regex`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN rust-regex 1m results -->
### rust-regex: 1-minute smoke campaign

* 1,203,072 patterns, 14 tables, 0 distinct findings; self-check 281,792 probes, 216 mismatches, 0 engine failures
* findings by kind: 186 selfcheck_mismatch (selfcheck)

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END rust-regex 1m results -->

<!-- BEGIN rust-regex 30s results -->
### Rust regex: 30s campaign

* 573,216 patterns, 7 tables, 0 distinct findings; self-check 281,792 probes, 216 mismatches, 0 engine failures
* findings by kind: 186 selfcheck_mismatch (selfcheck)

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END rust-regex 30s results -->

<!-- BEGIN rust-regex 10m results -->
### Rust regex: 10m campaign

* 10,844,032 patterns, 110 tables, 0 distinct findings; self-check 339,984 probes, 0 mismatches, 0 engine failures

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END rust-regex 10m results -->

<!-- BEGIN rust-regex 10m triage -->
### rust-regex: 10-minute campaign triage

* Clean: 10.8 M cases, 0 findings, self-check 0 mismatches.
<!-- END rust-regex 10m triage -->

<!-- BEGIN rust-regex 5m results -->
### Rust regex: 5m campaign

* 2,947,104 patterns, 31 tables, 0 distinct findings; self-check 339,984 probes, 0 mismatches, 0 engine failures

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END rust-regex 5m results -->
