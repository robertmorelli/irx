# Swift Regex 6.4 (unicodeScalar semantics, simple word boundaries)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py swift-regex`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN swift-regex 1m results -->
### swift-regex: 1-minute smoke campaign

* 57,344 patterns, 2 tables, 224 distinct findings; self-check 339,984 probes, 1,664 mismatches, 0 engine failures
* findings by kind: 224 timeout (batch), 200 selfcheck_mismatch (selfcheck)

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END swift-regex 1m results -->
