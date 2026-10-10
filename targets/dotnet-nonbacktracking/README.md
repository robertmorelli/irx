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

<!-- BEGIN dotnet-nonbacktracking 10m results -->
### .NET 9 Regex (NonBacktracking): 10m campaign

* 2,610,240 patterns, 28 tables, 6 distinct findings; self-check 336,272 probes, 0 mismatches, 0 engine failures
* findings by kind: 6 wrong_result

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 2 | wrong_result | `` | `"\n.-σa"` | `""` | `\W[\x{D}.].(?:(?:)\|\x{3C3})\Ba` | 00 |
| 2 | wrong_result | `` | `"aa aa"` | `"a"` | `(?:.(?:(?:\B\|\b)a){1,})*` | 00 |
| 2 | wrong_result | `` | `"\n.-a0"` | `""` | `(?:(?:\x{A}\|\S)a*\B){0,3}0` | 00 |

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END dotnet-nonbacktracking 10m results -->

<!-- BEGIN dotnet-nonbacktracking 10m triage -->
### dotnet-nonbacktracking: 10-minute campaign triage

* New: **IRX-DOTNET-6**. All 6 wrong results reduce to `^a (?:\Ba|\ba)+$` missing `"a aa"`: a loop of
  `\b`/`\B`-guarded alternatives under a leading `^`.
* Self-check clean, no timeouts. 2.6 M cases in 10 minutes.
<!-- END dotnet-nonbacktracking 10m triage -->
