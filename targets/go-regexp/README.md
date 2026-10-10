# Go regexp

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py go-regexp`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN go-regexp 1m results -->
### go-regexp: 1-minute smoke campaign

* 802,048 patterns, 10 tables, 50,366 distinct findings; self-check 281,792 probes, 11,160 mismatches, 0 engine failures
* findings by kind: 50,366 wrong_result, 190 selfcheck_mismatch (selfcheck)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 205 | wrong_result | `u` | `"ſ"` | `""` | `\w` | 00 |
| 136 | wrong_result | `u` | `"ſ"` | `""` | `.\b` | 00 |
| 113 | wrong_result | `u` | `"ſ"` | `""` | `\b.` | 00 |
| 102 | wrong_result | `u` | `"Σ"` | `""` | `\w` | 00 |
| 91 | wrong_result | `u` | `"é"` | `""` | `\w` | 00 |
| 81 | wrong_result | `u` | `"aſ"` | `""` | `a\w` | 00 |
| 72 | wrong_result | `u` | `"aſ"` | `""` | `a\B.` | 00 |
| 61 | wrong_result | `u` | `"ſ"` | `"aa"` | `\w` | 00 |

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END go-regexp 1m results -->
