# java.util.regex

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py java`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN java 1m results -->
### java: 1-minute smoke campaign

* 439,936 patterns, 6 tables, 1,626 distinct findings; self-check 281,792 probes, 3,492 mismatches, 0 engine failures
* findings by kind: 925 wrong_result, 544 syntax_error, 191 selfcheck_mismatch (selfcheck), 157 timeout (batch)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 6 | syntax_error | `u` | `"a"` | `""` | `(?<=(?:(?:)\|(?:)){1,1})a` | 04 |
| 6 | syntax_error | `u` | `"a"` | `""` | `(?<=(?:(?:)?){1,1})a` | 04 |
| 6 | syntax_error | `u` | `"a"` | `""` | `a(?<=(?:(?:)\|(?:)){1,1})` | 04 |
| 4 | syntax_error | `u` | `"a"` | `""` | `a(?<=(?:(?:)\|(?:)){0,2})` | 04 |
| 4 | syntax_error | `u` | `"a"` | `""` | `a(?<=(?:(?:)?){1,1})` | 04 |
| 2 | wrong_result | `su` | `""` | `"a\r"` | `(?:.$)*` | 33 |
| 2 | wrong_result | `su` | `""` | `"a\r"` | `(?:.$)*` | 03 |
| 2 | wrong_result | `u` | `"a\r"` | `""` | `a(?<!$)[^sK]` | 00 |

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END java 1m results -->
