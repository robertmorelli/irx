# nim-regex

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py nim-regex`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN nim-regex 1m results -->
### nim-regex: 1-minute smoke campaign

* 406,144 patterns, 6 tables, 13,122 distinct findings; self-check 281,792 probes, 18,100 mismatches, 0 engine failures
* findings by kind: 6,128 syntax_error, 4,680 wrong_result, 2,170 exception, 200 selfcheck_mismatch (selfcheck), 144 timeout (batch)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 37 | syntax_error | `u` | `"a"` | `""` | `(?<g0>a)` | 04 |
| 34 | syntax_error | `u` | `""` | `"a"` | `(?<g0>(?:))` | 04 |
| 16 | syntax_error | `u` | `"a"` | `""` | `(?<g0>(?:))a` | 04 |
| 14 | syntax_error | `u` | `"a"` | `""` | `a(?<g0>(?:))` | 04 |
| 6 | wrong_result | `u` | `"a"` | `""` | `a(?:(?<=(?:))){0,2}` | 00 |
| 4 | wrong_result | `u` | `"a"` | `""` | `a(?:(?!(?:))){0,2}` | 00 |
| 2 | wrong_result | `u` | `"aa"` | `""` | `a(?:(?=(?:))a){1,}` | 00 |
| 2 | wrong_result | `u` | `"aaaaaaaa"` | `"aaaaaa"` | `(?:(?:(?<!(?:))\|aa){2})*` | 33 |

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END nim-regex 1m results -->
