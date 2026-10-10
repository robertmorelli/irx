# Rust regex

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py rust-regex`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN rust-regex 1m results -->
### rust-regex: 1-minute smoke campaign

* 1,203,072 patterns, 14 tables, 0 distinct findings; self-check 281,792 probes, 216 mismatches, 0 engine failures
* findings by kind: 186 selfcheck_mismatch (selfcheck)

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END rust-regex 1m results -->
