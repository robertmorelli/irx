# Racket #px

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py racket`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN racket 1m results -->
### racket: 1-minute smoke campaign

* 210,240 patterns, 4 tables, 63,512 distinct findings; self-check 281,792 probes, 13,864 mismatches, 0 engine failures
* findings by kind: 37,382 wrong_result, 26,130 syntax_error, 169 selfcheck_mismatch (selfcheck)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 19 | syntax_error | `u` | `""` | `"a"` | `(?:)*` | 04 |
| 15 | syntax_error | `u` | `""` | `"a"` | `(?:){0,1}` | 04 |
| 11 | syntax_error | `u` | `""` | `"a"` | `(?:)+` | 04 |
| 7 | wrong_result | `u` | `"Σ"` | `""` | `\w` | 00 |
| 6 | syntax_error | `u` | `""` | `"a"` | `(?:){0,}` | 04 |
| 6 | wrong_result | `u` | `"aaaaΣaaa"` | `"a"` | `(?:\wa)*` | 00 |
| 5 | syntax_error | `u` | `"a"` | `""` | `a(?:){0,1}` | 04 |
| 4 | wrong_result | `u` | `"ſ"` | `""` | `\w` | 00 |

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END racket 1m results -->
