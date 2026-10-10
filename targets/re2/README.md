# RE2

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py re2`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN re2 1m results -->
### re2: 1-minute smoke campaign

* 802,048 patterns, 10 tables, 50,242 distinct findings; self-check 281,792 probes, 11,160 mismatches, 0 engine failures
* findings by kind: 50,242 wrong_result, 190 selfcheck_mismatch (selfcheck)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 22 | wrong_result | `u` | `"ſ"` | `""` | `\w` | 00 |
| 19 | wrong_result | `u` | `"Σ"` | `""` | `\w` | 00 |
| 17 | wrong_result | `u` | `"ſ"` | `"aa"` | `\w` | 00 |
| 13 | wrong_result | `u` | `"aſ"` | `""` | `a\w` | 00 |
| 12 | wrong_result | `u` | `"aaaaaaaſ"` | `"a"` | `(?:a\w)*` | 00 |
| 12 | wrong_result | `u` | `"aſ"` | `""` | `a\B.` | 00 |
| 10 | wrong_result | `u` | `"aaaaΣaaa"` | `"a"` | `(?:\wa)*` | 00 |
| 9 | wrong_result | `u` | `"aaaaaaaſ"` | `"a"` | `(?:a\B.)*` | 00 |

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END re2 1m results -->
