# Oniguruma 6.9 (C library)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py oniguruma`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN oniguruma 1m results -->
### oniguruma: 1-minute smoke campaign

* 406,144 patterns, 6 tables, 56,936 distinct findings; self-check 281,792 probes, 208 mismatches, 0 engine failures
* findings by kind: 53,586 syntax_error, 3,328 wrong_result, 193 selfcheck_mismatch (selfcheck), 22 exception

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 139 | syntax_error | `u` | `""` | `"a"` | `(?:\b)*` | 04 |
| 137 | syntax_error | `u` | `""` | `"a"` | `(?:\B)*` | 04 |
| 136 | syntax_error | `u` | `""` | `"a"` | `(?:$)*` | 04 |
| 127 | syntax_error | `u` | `""` | `"a"` | `(?:^)*` | 04 |
| 100 | syntax_error | `u` | `"a"` | `""` | `(?:$)?a` | 04 |
| 97 | syntax_error | `u` | `"a"` | `""` | `(?:\b)?a` | 04 |
| 94 | syntax_error | `u` | `""` | `"a"` | `(?:\b)?` | 04 |
| 93 | syntax_error | `u` | `""` | `"a"` | `(?:\B){0,1}` | 04 |

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END oniguruma 1m results -->
