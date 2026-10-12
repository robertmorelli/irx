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

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
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

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END dotnet-nonbacktracking 10m results -->

<!-- BEGIN dotnet-nonbacktracking 10m triage -->
### dotnet-nonbacktracking: 10-minute campaign triage

* New: **IRX-DOTNET-6**. All 6 wrong results reduce to `^a (?:\Ba|\ba)+$` missing `"a aa"`: a loop of
  `\b`/`\B`-guarded alternatives under a leading `^`.
* Self-check clean, no timeouts. 2.6 M cases in 10 minutes.
<!-- END dotnet-nonbacktracking 10m triage -->

<!-- BEGIN dotnet-nonbacktracking 5m results -->
### .NET 9 Regex (NonBacktracking): 5m campaign

* 650,176 patterns, 8 tables, 582 distinct findings; self-check 336,272 probes, 0 mismatches, 0 engine failures
* findings by kind: 580 wrong_span, 2 wrong_result

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 23 | wrong_span | `` | `"aaaaaaaa"` | `""` | `(?:a{2,}?){0,}a` | 00 |
| 13 | wrong_span | `` | `"aaaaaaaa"` | `""` | `(?:a{2,3}){0,}a` | 00 |
| 12 | wrong_span | `` | `"aaaaaaaa"` | `""` | `(?:a{3,}?){0,3}a` | 00 |
| 10 | wrong_span | `` | `"aéa"` | `""` | `(?:a\|.*?)a` | 00 |
| 6 | wrong_span | `` | `"aaaaaaaa"` | `""` | `(?:a{2,3})+a` | 00 |
| 5 | wrong_span | `` | `"aaaaaaaa"` | `""` | `(?:a{1,2}a){0,}a` | 00 |
| 4 | wrong_span | `` | `"aaaaaaaa"` | `"aa"` | `(?:a{2,}?){0,}a` | 00 |
| 4 | wrong_span | `` | `"aaaaaaaa"` | `""` | `(?:a+?a){0,}a` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END dotnet-nonbacktracking 5m results -->

<!-- BEGIN dotnet-nonbacktracking 30m results -->
### .NET 9 Regex (NonBacktracking): 30m campaign

* 3,161,440 patterns, 33 tables, 5,996 distinct findings; self-check 336,272 probes, 0 mismatches, 0 engine failures
* findings by kind: 3,051 wrong_capture, 2,941 wrong_span, 2 timeout (batch), 2 wrong_result

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 9 | wrong_span | `` | `"aa"` | `""` | `(?:aa\|()\|a)a` | 00 |
| 8 | wrong_span | `` | `"aa"` | `""` | `(?:aa\|a*?)a` | 00 |
| 6 | wrong_capture | `` | `"aa"` | `""` | `(?:aa\|a*?)a` | 00 |
| 5 | wrong_span | `` | `"a😀a"` | `"a😀a😀"` | `(?:a\|.*?)a` | 02 |
| 5 | wrong_capture | `` | `"a😀a"` | `"a😀a😀"` | `(?:a\|.*?)a` | 02 |
| 4 | wrong_capture | `` | `"aa"` | `""` | `(?:aa\|()\|a)a` | 00 |
| 4 | wrong_span | `` | `"aa"` | `""` | `(?:aa\|(?:)\|a)a` | 00 |
| 4 | wrong_capture | `` | `"  "` | `""` | `(?:a\|.*?)\W` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END dotnet-nonbacktracking 30m results -->

<!-- BEGIN dotnet-nonbacktracking long-10m results -->
### .NET 9 Regex (NonBacktracking): long-10m campaign

* 192,160 patterns, 3 tables, 216 distinct findings; self-check 336,272 probes, 0 mismatches, 0 engine failures
* findings by kind: 108 wrong_capture, 108 wrong_span

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 7 | wrong_span | `` | `"- kß "` | `"-K0ß"` | `(?:a\|.*?)\W` | 02 |
| 7 | wrong_capture | `` | `"- kß "` | `"-K0ß"` | `(?:a\|.*?)\W` | 02 |
| 4 | wrong_span | `` | `"- kß "` | `"-K0ß"` | `(?:a\|\D*?).` | 02 |
| 4 | wrong_capture | `` | `"- kß "` | `"-K0ß"` | `(?:a\|\D*?).` | 02 |
| 3 | wrong_span | `` | `"- kß "` | `"-K0ß"` | `(?:a\|(?:..)*?)\D` | 02 |
| 3 | wrong_capture | `` | `"- kß "` | `"-K0ß"` | `(?:a\|(?:..)*?)\D` | 02 |
| 2 | wrong_capture | `` | `"- kß "` | `"-K0ß"` | `(?:a\|\D{0,}?).` | 02 |
| 2 | wrong_span | `` | `"- kß "` | `"-K0ß"` | `(?:a\|\D{0,}?).` | 02 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END dotnet-nonbacktracking long-10m results -->
