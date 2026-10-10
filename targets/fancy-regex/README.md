# fancy-regex

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py fancy-regex`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN fancy-regex 1m results -->
### fancy-regex: 1-minute smoke campaign

* 385,504 patterns, 5 tables, 44,720 distinct findings; self-check 281,792 probes, 216 mismatches, 0 engine failures
* findings by kind: 44,708 syntax_error, 186 selfcheck_mismatch (selfcheck), 12 exception

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 403 | syntax_error | `u` | `""` | `"a"` | `(?:)*` | 04 |
| 295 | syntax_error | `u` | `""` | `"a"` | `(?:){0,1}` | 04 |
| 270 | syntax_error | `u` | `"a"` | `""` | `(?:)?a` | 04 |
| 252 | syntax_error | `u` | `""` | `"a"` | `(?:)?` | 04 |
| 219 | syntax_error | `u` | `"a"` | `""` | `a(?:)?` | 04 |
| 178 | syntax_error | `u` | `"a"` | `""` | `a(?:){0,1}` | 04 |
| 173 | syntax_error | `u` | `""` | `"a"` | `(?:)+` | 04 |
| 158 | syntax_error | `u` | `"a"` | `""` | `(?:){0,1}a` | 04 |

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END fancy-regex 1m results -->
