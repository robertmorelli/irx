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

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END dotnet-compiled 1m results -->

<!-- BEGIN dotnet-compiled 10m results -->
### .NET 9 Regex (Compiled): 10m campaign

* 848,640 patterns, 10 tables, 1,887 distinct findings; self-check 336,272 probes, 0 mismatches, 0 engine failures
* findings by kind: 986 exception, 759 timeout (batch), 142 wrong_result

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 10 | exception | `` | `""` | `"a"` | `(?<=(?:)*?)` | 08 |
| 8 | exception | `` | `"a"` | `""` | `(?<=(?:)*?)a` | 08 |
| 6 | exception | `` | `"a"` | `""` | `a(?<=(?:)*?)` | 08 |
| 6 | exception | `` | `"a"` | `""` | `a\|(?<!(?:)*?)` | 08 |
| 6 | exception | `` | `"a"` | `""` | `a(?<=(?:){0,1}?)` | 08 |
| 4 | exception | `` | `""` | `"a"` | `(?<=(?:)??)` | 08 |
| 4 | exception | `` | `""` | `"a"` | `(?<=(?:){0,1}?)` | 08 |
| 4 | exception | `` | `"a"` | `""` | `(?<!(?:)*?)\|a` | 08 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END dotnet-compiled 10m results -->

<!-- BEGIN dotnet-compiled 10m triage -->
### dotnet-compiled: 10-minute campaign triage

* New: **IRX-DOTNET-4** (`ArgumentOutOfRangeException ... 'newSize'` from `(?:(?:a|(?:\B){2,}?)a)*a` on `"aaa"`)
  and **IRX-DOTNET-5** (lazy loops with a lower bound inside a loop or lookbehind: `(?:(?:){2,3}?a)*` misses `"a"`).
* The 986 exceptions are mostly IRX-DOTNET-2 (`(?<=(?:)*?)` and other lazy empty loops in lookarounds), plus IRX-DOTNET-4.
* 759 timeouts, not investigated: Compiled pays ~1 ms of IL generation per pattern.
<!-- END dotnet-compiled 10m triage -->

<!-- BEGIN dotnet-compiled 5m results -->
### .NET 9 Regex (Compiled): 5m campaign

* 255,808 patterns, 4 tables, 1,061 distinct findings; self-check 336,272 probes, 0 mismatches, 0 engine failures
* findings by kind: 767 exception, 182 timeout (batch), 68 wrong_result, 44 wrong_span

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 12 | exception | `` | `"a"` | `""` | `(?<=(?:)*?)a` | 08 |
| 4 | exception | `` | `"a"` | `""` | `a(?<=()*?)` | 08 |
| 4 | exception | `` | `"a"` | `""` | `a(?<=(?:){0,1}?)` | 08 |
| 4 | wrong_result | `` | `"a"` | `"K"` | `(?:(?:){2,}?a){0,2}` | 00 |
| 4 | exception | `` | `"a"` | `""` | `(?<=()*?)a` | 08 |
| 4 | exception | `` | `"a"` | `""` | `a(?<=(?:)??)` | 08 |
| 3 | exception | `` | `""` | `"a"` | `(?:(?<!(?:)??))*` | 08 |
| 3 | exception | `` | `"a"` | `""` | `(?<=(?:aa)??)a` | 08 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END dotnet-compiled 5m results -->
