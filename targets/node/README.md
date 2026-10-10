# V8 14.1 (Node 25.8) - older V8, excluded from the ledger

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py node`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN node 1m results -->
### node: 1-minute smoke campaign

* 437,888 patterns, 6 tables, 2,245 distinct findings; self-check 1,628,352 probes, 80 mismatches, 0 engine failures
* findings by kind: 2,098 wrong_result, 147 timeout (batch), 80 selfcheck_mismatch (selfcheck)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 200 | wrong_result | `mu` | `""` | `"😀"` | `(?:)` | 03 |

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END node 1m results -->
