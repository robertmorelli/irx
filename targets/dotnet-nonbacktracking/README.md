# .NET 9 Regex (NonBacktracking)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py dotnet-nonbacktracking`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN dotnet-nonbacktracking 1m results -->
### dotnet-nonbacktracking: 1-minute smoke campaign

* 252,736 patterns, 4 tables, 60 distinct findings; self-check 281,792 probes, 10,252 mismatches, 0 engine failures
* findings by kind: 200 selfcheck_mismatch (selfcheck), 60 wrong_result

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 10 | wrong_result | `u` | `"a"` | `""` | `a\x{1F600}?` | 00 |
| 8 | wrong_result | `u` | `"a"` | `""` | `a\x{1F600}*` | 00 |
| 6 | wrong_result | `u` | `""` | `"a"` | `\x{1F600}?` | 00 |
| 6 | wrong_result | `u` | `"a"` | `""` | `\x{1F600}?a` | 00 |
| 2 | wrong_result | `u` | `"a\r"` | `""` | `a\W\x{1F600}*` | 00 |
| 2 | wrong_result | `u` | `"aaa"` | `""` | `\x{1F600}*aaa` | 00 |
| 2 | wrong_result | `su` | `"a\nàaa"` | `""` | `(?:\x{E0}?(?:\B\|\b)a.){2}` | 00 |
| 2 | wrong_result | `u` | `"a"` | `"aa"` | `a\x{1F600}{0,1}` | 00 |

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END dotnet-nonbacktracking 1m results -->
