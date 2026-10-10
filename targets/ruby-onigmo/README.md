# Ruby Onigmo

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py ruby-onigmo`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN ruby-onigmo 1m results -->
### ruby-onigmo: 1-minute smoke campaign

* 428,672 patterns, 6 tables, 22,384 distinct findings; self-check 281,792 probes, 576 mismatches, 0 engine failures
* findings by kind: 17,508 wrong_result, 4,764 syntax_error, 180 selfcheck_mismatch (selfcheck), 112 timeout (batch)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 33 | wrong_result | `u` | `"Σ"` | `""` | `\w` | 00 |
| 28 | wrong_result | `u` | `"ſ"` | `""` | `\w` | 00 |
| 27 | wrong_result | `u` | `"aaaaΣaaa"` | `"a"` | `(?:\wa)*` | 00 |
| 14 | wrong_result | `u` | `"aaaaaaaſ"` | `"a"` | `(?:a\w)*` | 00 |
| 10 | wrong_result | `u` | `"ſ"` | `"aa"` | `\w` | 00 |
| 9 | wrong_result | `u` | `"aaéaaaaa"` | `"a"` | `(?:aa\wa){0,2}` | 00 |
| 9 | wrong_result | `u` | `"à"` | `""` | `\w` | 00 |
| 9 | wrong_result | `u` | `"aaéaaaaa"` | `"a"` | `(?:\wa)*` | 00 |

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END ruby-onigmo 1m results -->
