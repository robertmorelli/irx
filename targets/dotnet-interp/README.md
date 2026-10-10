# .NET 9 Regex (interpreter)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py dotnet-interp`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN dotnet-interp 1m results -->
### dotnet-interp: 1-minute smoke campaign

* 117,408 patterns, 3 tables, 246 distinct findings; self-check 281,792 probes, 10,252 mismatches, 0 engine failures
* findings by kind: 216 timeout (batch), 200 selfcheck_mismatch (selfcheck), 26 wrong_result, 4 exception

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 2 | exception | `u` | `"a"` | `"aa"` | `(?=(?:)+?a)a` | 08 |
| 2 | wrong_result | `u` | `"a"` | `""` | `\x{1F600}*a` | 00 |
| 1 | wrong_result | `u` | `"aaa"` | `"aaſ"` | `(?:a\|(?:.(?:(?!a))*?){2,}){3,3}` | 33 |
| 1 | wrong_result | `u` | `"aaa"` | `"aaſ"` | `(?:a\|(?:.(?:(?!a))*?){2,}){3,3}` | 03 |
| 1 | wrong_result | `u` | `"aaaa"` | `"aa"` | `(?:(?:(?:)*?aa){2,2})?` | 33 |
| 1 | wrong_result | `u` | `"aaa"` | `"aaſ"` | `(?:a\|\w{2,}(?:)*?){3}` | 33 |
| 1 | wrong_result | `u` | `"aaaaaa"` | `"aaaaSa"` | `(?:a(?:[^\x{2028}\x{131}](?:(?:)+?){0,1})+){3}` | 03 |
| 1 | wrong_result | `u` | `"aaaaaa"` | `"aaaaSa"` | `(?:a(?:[^\x{2028}\x{131}](?:(?:)+?){0,1})+){3}` | 33 |

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END dotnet-interp 1m results -->
