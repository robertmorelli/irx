# Tcl ARE

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py tcl`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN tcl 1m results -->
### tcl: 1-minute smoke campaign

* 307,680 patterns, 5 tables, 48,324 distinct findings; self-check 281,792 probes, 21,630 mismatches, 0 engine failures
* findings by kind: 43,542 wrong_result, 4,782 syntax_error, 200 selfcheck_mismatch (selfcheck)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 97 | wrong_result | `u` | `"aa"` | `""` | `a\Ba` | 00 |
| 91 | wrong_result | `u` | `"a"` | `""` | `\ba` | 00 |
| 72 | wrong_result | `u` | `"a"` | `""` | `a\b` | 00 |
| 50 | wrong_result | `mu` | `""` | `"\n"` | `(?:)` | 03 |
| 45 | wrong_result | `mu` | `""` | `"\n"` | `(?:)` | 33 |
| 45 | wrong_result | `u` | `"aaaaaaaa"` | `""` | `(?:a\Ba)+` | 00 |
| 44 | wrong_result | `u` | `"a"` | `"aa"` | `\ba` | 00 |
| 44 | wrong_result | `u` | `"aaaaaaaa"` | `"a"` | `(?:a\Ba)*` | 00 |

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END tcl 1m results -->
