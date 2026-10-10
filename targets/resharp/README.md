# RE# (resharp)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py resharp`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN resharp 1m results -->
### resharp: 1-minute smoke campaign

* 104,096 patterns, 3 tables, 48,596 distinct findings; self-check 281,792 probes, 39,008 mismatches, 0 engine failures
* findings by kind: 43,046 syntax_error, 5,550 wrong_result, 141 syntax_error (selfcheck), 54 selfcheck_mismatch (selfcheck)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 219 | syntax_error | `u` | `""` | `"a"` | `(?:)*?` | 04 |
| 191 | syntax_error | `u` | `"a"` | `""` | `a+?` | 04 |
| 141 | syntax_error | `u` | `""` | `"a"` | `(?:){0,1}?` | 04 |
| 87 | syntax_error | `u` | `""` | `"a"` | `(?:){0,}?` | 04 |
| 35 | syntax_error | `u` | `"a"` | `""` | `a{1,1}?` | 04 |
| 30 | syntax_error | `u` | `"a"` | `""` | `a(?<=(?:))` | 04 |
| 30 | wrong_result | `u` | `"aaaaaaaſ"` | `""` | `(?:a.)+` | 00 |
| 28 | syntax_error | `u` | `"aaaaaaaa"` | `"a"` | `(?:aaaa){0,2}?` | 04 |

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END resharp 1m results -->
