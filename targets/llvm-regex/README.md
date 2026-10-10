# LLVM Regex (POSIX ERE, translated)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py llvm-regex`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN llvm-regex 1m results -->
### llvm-regex: 1-minute smoke campaign

* 132,768 patterns, 3 tables, 62,472 distinct findings; self-check 281,792 probes, 95,050 mismatches, 0 engine failures
* findings by kind: 62,472 wrong_result, 156 selfcheck_mismatch (selfcheck)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 159 | wrong_result | `u` | `"aaaaaaaſ"` | `"a"` | `(?:a.)*` | 00 |
| 150 | wrong_result | `u` | `"aaaaaaaſ"` | `""` | `(?:a.)+` | 00 |
| 93 | wrong_result | `u` | `"ſ"` | `""` | `\w` | 00 |
| 80 | wrong_result | `u` | `"aſ"` | `""` | `a\w` | 00 |
| 71 | wrong_result | `u` | `"aaaaaaaſ"` | `"a"` | `(?:aaa.){0,2}` | 00 |
| 67 | wrong_result | `u` | `"aaaaaſ"` | `"a"` | `(?:a.)*` | 00 |
| 59 | wrong_result | `u` | `"aſ"` | `""` | `a.` | 00 |
| 53 | wrong_result | `u` | `"aaaaaaaſ"` | `"a"` | `(?:a\w)*` | 00 |

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END llvm-regex 1m results -->
