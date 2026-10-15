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

<!-- BEGIN dotnet-compiled 30m results -->
### .NET 9 Regex (Compiled): 30m campaign

* 1,318,432 patterns, 15 tables, 8,648 distinct findings; self-check 336,272 probes, 0 mismatches, 0 engine failures
* findings by kind: 6,327 exception, 1,509 timeout (batch), 336 wrong_result, 240 wrong_span, 236 wrong_capture

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 70 | exception | `` | `""` | `"a"` | `(?<=(?:)*?)` | 08 |
| 59 | exception | `` | `""` | `"a"` | `(?<=(?:)??)` | 08 |
| 35 | exception | `` | `"a"` | `""` | `(?<=(?:)*?)a` | 08 |
| 29 | exception | `` | `""` | `"a"` | `(?<=()??)` | 08 |
| 29 | exception | `` | `"a"` | `""` | `a(?<=(?:)*?)` | 08 |
| 25 | exception | `` | `""` | `"a"` | `(?<=()*?)` | 08 |
| 21 | exception | `` | `"a"` | `""` | `a\|(?<!(?:)??)` | 08 |
| 18 | exception | `` | `""` | `"a"` | `(?<=(?:){0,1}?)` | 08 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END dotnet-compiled 30m results -->

<!-- BEGIN dotnet-compiled long-10m results -->
### .NET 9 Regex (Compiled): long-10m campaign

* 168,096 patterns, 3 tables, 586 distinct findings; self-check 336,272 probes, 0 mismatches, 0 engine failures
* findings by kind: 474 exception, 47 wrong_span, 46 wrong_capture, 19 long_result

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 19 | wrong_span | `` | `"- kß "` | `"-K0ß"` | `\D+\B` | 03 |
| 19 | wrong_capture | `` | `"- kß "` | `"-K0ß"` | `\D+\B` | 03 |
| 12 | exception | `` | `"- kß "` | `"-K0ß"` | `\D\|(?<!(?:)*?)` | 08 |
| 8 | exception | `` | `"- kß "` | `"-K0ß"` | `(?<=(?:)??)\D` | 08 |
| 6 | exception | `` | `"àKſékΣk"` | `"àKéàkΣk"` | `(?<=()??)[^b\x{E0}]` | 08 |
| 6 | exception | `` | `"- kß "` | `"-K0ß"` | `(?<=(?:)*?)\D` | 08 |
| 6 | exception | `` | `"- kß "` | `"-K0ß"` | `(?<=(?:)*?).\B` | 08 |
| 5 | exception | `` | `"- kß "` | `"-K0ß"` | `()\|(?<!(?:)*?)` | 08 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END dotnet-compiled long-10m results -->

<!-- BEGIN dotnet-compiled r10 results -->
### .NET 9 Regex (Compiled): r10 campaign

* 339,424 patterns, 5 tables, 1,386 distinct findings
* findings by kind: 634 exception, 337 wrong_span, 258 wrong_result, 157 wrong_capture

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 22 | exception | `` | `"a"` | `""` | `(?<=(){0,1}?)a` | 08 |
| 16 | exception | `` | `""` | `"a"` | `(?<=(?:){0,1}?)` | 08 |
| 12 | exception | `` | `"a"` | `""` | `(?<=(){0,}?)a` | 08 |
| 12 | exception | `` | `"a"` | `""` | `(?<=(?:){0,1}?)a` | 08 |
| 10 | exception | `` | `""` | `"a"` | `(?x:(?:(?<!(?:){0,1}?))*)` | 08 |
| 8 | exception | `` | `""` | `"a"` | `(?<=(?:){0,}?)` | 08 |
| 8 | exception | `` | `""` | `"a"` | `(?:(?<=(){0,1}?))+` | 08 |
| 8 | exception | `` | `""` | `"a"` | `(?:(?<=(?:){0,1}?))*` | 08 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END dotnet-compiled r10 results -->

<!-- BEGIN dotnet-compiled r2h results -->
### .NET 9 Regex (Compiled): r2h campaign

* 4,107,168 patterns, 43 tables, 1,577 distinct findings; self-check 3,457,024 probes, 0 mismatches, 0 engine failures
* findings by kind: 739 wrong_span, 466 wrong_result, 366 wrong_capture, 6 timeout (batch)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 92 | wrong_result | `` | `"aa"` | `""` | `\D+\Ba` | 00 |
| 63 | wrong_span | `` | `"aa"` | `""` | `\D+\Ba` | 00 |
| 56 | wrong_result | `` | `"aa"` | `""` | `\D{1,2}\Ba` | 00 |
| 34 | wrong_span | `` | `"aa"` | `""` | `\D{1,2}\Ba` | 00 |
| 33 | wrong_capture | `` | `"aa"` | `""` | `\D+\Ba` | 00 |
| 22 | wrong_capture | `` | `"aa"` | `""` | `\D{1,2}\Ba` | 00 |
| 22 | wrong_result | `` | `"aa"` | `""` | `\D{1,}\Ba` | 00 |
| 15 | wrong_span | `` | `"aa"` | `""` | `\D{1,}\Ba` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END dotnet-compiled r2h results -->
<!-- BEGIN dotnet-compiled r2h triage -->
### dotnet-compiled: r2h (2-hour) campaign triage

The host rolls forward to the newest installed runtime: this campaign ran on .NET 11.0.0-rc.1 (the results title says .NET 9).

* New: IRX-DOTNET-12 (a loop over `\D`, `\W` or `\P{Nd}` before `\B` never gives characters back: `^\D+\Ba$` fails on `"aa"`), about 940 findings; IRX-DOTNET-13 (a loop with minimum ≥ 1 over `(loop|empty)` ignores the empty branch: `(?:a+|)+` never matches `""`), about 210. Both are regressions since .NET 9.0.4 (present in 10.0.12 and 11 RC 1, interpreter and Compiled).
* Known: IRX-DOTNET-8's family (nested counted loops whose spans differ from Perl, also on .NET 9: `(?:(?:.{2,2}|a)+){2,2}` on `"aaaaaaϑ"` is `[0,6)`, Perl `[0,7)`), about 290.
* Model gap, fixed: .NET numbers unnamed groups before named ones, so in `(?<g1>a)|aa()\1` the `\1` is the empty `()`; backreferences are now printed by .NET numbering (named groups as `\k<gN>`). 128 findings.
* Self-check clean.
<!-- END dotnet-compiled r2h triage -->
