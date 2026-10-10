# V8 15.0 (Deno 2.9.7) - older V8, excluded from the ledger

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py deno`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN deno 1m results -->
### deno: 1-minute smoke campaign

* 433,792 patterns, 6 tables, 1,178 distinct findings; self-check 1,628,352 probes, 80 mismatches, 0 engine failures
* findings by kind: 1,048 wrong_result, 130 timeout (batch), 80 selfcheck_mismatch (selfcheck)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 201 | wrong_result | `mu` | `""` | `"😀"` | `(?:)` | 03 |

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END deno 1m results -->
