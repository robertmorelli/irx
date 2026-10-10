# .NET 9 Regex (Compiled)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py dotnet-compiled`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN dotnet-compiled 1m results -->
### dotnet-compiled: 1-minute smoke campaign

* 96,256 patterns, 2 tables, 142 distinct findings; self-check 281,792 probes, 10,252 mismatches, 0 engine failures
* findings by kind: 200 selfcheck_mismatch (selfcheck), 92 exception, 26 wrong_result, 24 timeout (batch)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 2 | exception | `u` | `"a"` | `""` | `a(?<=(?:)??)` | 08 |
| 2 | exception | `u` | `"a"` | `""` | `a(?<=(?:){0,1}?)` | 08 |
| 2 | exception | `u` | `"akaa"` | `"a"` | `(?:(?<!(?:){0,1}?a)a.)*` | 08 |
| 1 | wrong_result | `u` | `"aaaa"` | `""` | `(?:a\x{1F600}*a){1,2}` | 00 |
| 1 | wrong_result | `u` | `"aa"` | `"aaaaa"` | `(?:(?:(?:){2,3}?a){2})+` | 33 |
| 1 | wrong_result | `u` | `"aa"` | `"aaaaa"` | `(?:(?:(?:){2,3}?a){2})+` | 03 |

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END dotnet-compiled 1m results -->
