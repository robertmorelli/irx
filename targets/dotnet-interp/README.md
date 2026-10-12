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

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END dotnet-interp 1m results -->

<!-- BEGIN dotnet-interp 10m results -->
### .NET 9 Regex (interpreter): 10m campaign

* 699,840 patterns, 8 tables, 2,459 distinct findings; self-check 336,272 probes, 0 mismatches, 0 engine failures
* findings by kind: 2,204 timeout (batch), 226 wrong_result, 29 exception

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 16 | wrong_result | `` | `"aa"` | `""` | `(?:a(?:)+?)+` | 00 |
| 8 | wrong_result | `` | `"aa"` | `"S"` | `(?:a(?:)+?)*` | 00 |
| 8 | exception | `` | `""` | `"a"` | `(?!(?:)+?a)` | 08 |
| 6 | wrong_result | `` | `"aa"` | `"0"` | `(?:a(?:)+?)*` | 00 |
| 2 | wrong_result | `` | `"aaaaaaaa"` | `"aaaaaa"` | `(?:(?:aa(?:)*?){2}){0,}` | 03 |
| 2 | wrong_result | `` | `"aaaaaaaa"` | `"a"` | `(?:(?:aa(?:)+?){0,2}){0,2}` | 00 |
| 2 | exception | `` | `"aaaaaaaa"` | `""` | `(?:a(?<=(?:)+?)aaa)+` | 08 |
| 2 | wrong_result | `` | `"aa"` | `"S"` | `(?:a(?:(?![k-s]))+?)*` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END dotnet-interp 10m results -->

<!-- BEGIN dotnet-interp 10m triage -->
### dotnet-interp: 10-minute campaign triage

* New: **IRX-DOTNET-3**. Nearly all 226 wrong results are a lazy loop over a nullable body inside another loop,
  e.g. `(?:a(?:)+?)+` on `"aa"` → `[1,2)`.
* The 29 exceptions are the IRX-DOTNET-1 family (`(?!(?:)+?a)` → `IndexOutOfRangeException`).
* 2,204 timeouts; triage replays reproduced only 252 of 2,435 findings (mostly the wrong results), so the
  timeouts look load-induced. The self-check finished in 1.6 s with 0 mismatches.
<!-- END dotnet-interp 10m triage -->

<!-- BEGIN dotnet-interp 5m results -->
### .NET 9 Regex (interpreter): 5m campaign

* 183,456 patterns, 3 tables, 1,354 distinct findings; self-check 336,272 probes, 0 mismatches, 0 engine failures
* findings by kind: 663 timeout (batch), 529 wrong_span, 154 wrong_result, 7 exception, 1 tier_mismatch

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 6 | wrong_result | `` | `"aa"` | `""` | `(?:a()+?)+` | 00 |
| 5 | wrong_span | `` | `""` | `"a"` | `(?:(?:)+?)+` | 02 |
| 4 | wrong_span | `` | `""` | `"a"` | `(?:(?:)+?)*` | 02 |
| 4 | wrong_span | `` | `""` | `"a"` | `(?:()+?)*` | 02 |
| 3 | wrong_span | `` | `"aa"` | `"aK"` | `(?:()*?a){2,}` | 03 |
| 3 | wrong_span | `` | `"a"` | `" a"` | `(?:a()+?)+` | 02 |
| 3 | wrong_span | `` | `"aa"` | `"aK"` | `(?:a()*?){2,}` | 03 |
| 3 | wrong_span | `` | `"a"` | `"aK"` | `(?:a(?:)+?)+` | 02 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END dotnet-interp 5m results -->

<!-- BEGIN dotnet-interp 30m results -->
### .NET 9 Regex (interpreter): 30m campaign

* 983,456 patterns, 11 tables, 8,969 distinct findings; self-check 336,272 probes, 0 mismatches, 0 engine failures
* findings by kind: 4,817 timeout (batch), 1,938 wrong_span, 1,865 wrong_capture, 228 wrong_result, 110 exception, 10 protocol (batch), 1 tier_mismatch

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 21 | wrong_span | `` | `""` | `"a"` | `(?:(?:)+?)*` | 02 |
| 20 | wrong_span | `` | `""` | `"a"` | `(?:(?:)+?)+` | 02 |
| 11 | wrong_span | `` | `""` | `"a"` | `(?:()+?)*` | 02 |
| 10 | wrong_span | `` | `""` | `"a"` | `(?:(?:$)+?)*` | 00 |
| 9 | wrong_span | `` | `""` | `"a"` | `(?:()+?)+` | 02 |
| 7 | wrong_span | `` | `"aa"` | `"aaa"` | `a(?:)+?a` | 02 |
| 6 | wrong_span | `` | `"aa"` | `""` | `a(?:)+?a` | 00 |
| 6 | wrong_span | `` | `""` | `"a"` | `(?:()+?){0,}` | 02 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END dotnet-interp 30m results -->

<!-- BEGIN dotnet-interp long-10m results -->
### .NET 9 Regex (interpreter): long-10m campaign

* 93,184 patterns, 2 tables, 234 distinct findings; self-check 336,272 probes, 0 mismatches, 0 engine failures
* findings by kind: 97 wrong_span, 95 wrong_capture, 36 exception, 6 long_result

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 19 | wrong_capture | `` | `"- kß "` | `"-K0ß"` | `\D+\B` | 03 |
| 19 | wrong_span | `` | `"- kß "` | `"-K0ß"` | `\D+\B` | 03 |
| 3 | exception | `` | `"- kß "` | `"-K0ß"` | `(?:(?!()+?[^k\-].).)*` | 08 |
| 3 | exception | `` | `"- kß "` | `"-K0ß"` | `.(?<!\B(?:)+?)` | 08 |
| 3 | wrong_span | `` | `"- kß "` | `"-K0ß"` | `\D{1,}\B` | 03 |
| 3 | wrong_capture | `` | `"- kß "` | `"-K0ß"` | `\D{1,}\B` | 03 |
| 2 | wrong_capture | `` | `"- kß "` | `"-K0ß"` | `(?:()+?)*` | 02 |
| 2 | exception | `` | `"- kß "` | `"-K0ß"` | `(?:[^\x{D83D}\x{130}](?<=(?:)+?))+?\s` | 08 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END dotnet-interp long-10m results -->
