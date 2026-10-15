# fancy-regex

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py fancy-regex`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN fancy-regex 1m results -->
### fancy-regex: 1-minute smoke campaign

* 385,504 patterns, 5 tables, 44,720 distinct findings; self-check 281,792 probes, 216 mismatches, 0 engine failures
* findings by kind: 44,708 syntax_error, 186 selfcheck_mismatch (selfcheck), 12 exception

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 403 | syntax_error | `u` | `""` | `"a"` | `(?:)*` | 04 |
| 295 | syntax_error | `u` | `""` | `"a"` | `(?:){0,1}` | 04 |
| 270 | syntax_error | `u` | `"a"` | `""` | `(?:)?a` | 04 |
| 252 | syntax_error | `u` | `""` | `"a"` | `(?:)?` | 04 |
| 219 | syntax_error | `u` | `"a"` | `""` | `a(?:)?` | 04 |
| 178 | syntax_error | `u` | `"a"` | `""` | `a(?:){0,1}` | 04 |
| 173 | syntax_error | `u` | `""` | `"a"` | `(?:)+` | 04 |
| 158 | syntax_error | `u` | `"a"` | `""` | `(?:){0,1}a` | 04 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END fancy-regex 1m results -->

<!-- BEGIN fancy-regex 10m results -->
### fancy-regex: 10m campaign

* 4,577,312 patterns, 47 tables, 6,835 distinct findings; self-check 339,984 probes, 0 mismatches, 0 engine failures
* findings by kind: 6,834 exception, 1 timeout (batch)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 2 | exception | `u` | `"a"` | `"aaaaaaaaa-éK\nAσKσKΣk "` | `a(?=(?:\b\|[^A0]\|.)*)` | 08 |
| 2 | exception | `u` | `""` | `"aaaaaéK\nAσKσKΣk "` | `(?:(?:(?:(?:(?!(?:))\|a\|a)*)?)+)+` | 08 |
| 2 | exception | `u` | `""` | `"aaaaaaaaaaaaaaaaaAσKσKΣk "` | `(?:(?:a\|(?:)\|(?!(?:))){0,2}){0,}` | 08 |
| 2 | exception | `u` | `"a"` | `"aaaaaAσKσKΣk "` | `(?:a(?=(?:(?:\B\|a){0,2})*))+` | 08 |
| 2 | exception | `u` | `""` | `"aaaaaaa\nAσKσKΣk "` | `(?:(?:\B\|a\|(?:)){0,2})+` | 08 |
| 2 | exception | `su` | `""` | `"aaaaaaaaK\nAσKσKΣk "` | `(?:(?:\B\|.)*){0,}a\|(?:)` | 08 |
| 2 | exception | `u` | `""` | `"a.a😀ſ-😀Kı-éK\nAσKσKΣk "` | `(?:(?:\S\|\b){0,2})*` | 08 |
| 2 | exception | `u` | `""` | `"a.a😀a😀aı-éK\nAσKσKΣk "` | `(?:(?:\b\|\S){0,2})*` | 08 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END fancy-regex 10m results -->

<!-- BEGIN fancy-regex 10m triage -->
### fancy-regex: 10-minute campaign triage

* No wrong results; self-check clean; 4.6 M cases.
* All 6,834 exceptions are `is_match` returning `Err` on long subjects with nested nullable or overlapping
  alternatives (`a(?=(?:\b|[^A0]|.)*)` on a 20-char subject): exponential backtracking hitting fancy-regex's
  backtrack limit (1,000,000 steps by default), a documented resource limit rather than a bug.
<!-- END fancy-regex 10m triage -->

<!-- BEGIN fancy-regex 5m results -->
### fancy-regex: 5m campaign

* 1,621,504 patterns, 18 tables, 3,005 distinct findings; self-check 339,984 probes, 0 mismatches, 0 engine failures
* findings by kind: 3,005 exception

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 3 | exception | `iu` | `"kΣ"` | `"aaa"` | `(?:(?:\b\|(?:a\|){0,3})+){0,3}[K\x{212A}][^a\x{E9}]` | 08 |
| 3 | exception | `u` | `"aaaaaa"` | `""` | `(?:(?:(?:a\b){0,}(?:(?:a*){3,})*a){3,}){2}` | 08 |
| 3 | exception | `su` | `" a\nß-S"` | `""` | `(?:\s(?:(?:[^a ]\|(?:(?:)\|\b\|.){0,1})+)*.){2,2}` | 08 |
| 3 | exception | `su` | `" \naa"` | `""` | `(?:\s(?:(?:(?:(?:.\|\B)*){0,3}){1,})+){2,}` | 08 |
| 3 | exception | `u` | `"ka"` | `"aaa"` | `(?:(?:(?:a*){0,2}a?)+\|(?=(?:)))+[k-s]a` | 08 |
| 3 | exception | `u` | `" a\naaaa"` | `""` | `(?:\s(?:(?:(?:a\|\D)*)+\|(?<!()))+a){2}` | 08 |
| 3 | exception | `u` | `" a\na-a"` | `""` | `(?:\W(?:(?:.*\|\|\b){0,3})+a){3}` | 08 |
| 3 | exception | `u` | `"aaaaaaaa"` | `"aaaaa"` | `(?:(?:a(?:(?:\|a){0,2}\|\B){0,3}a){2,}){2,2}` | 08 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END fancy-regex 5m results -->

<!-- BEGIN fancy-regex 30m results -->
### fancy-regex: 30m campaign

* 8,674,752 patterns, 88 tables, 6,019 distinct findings; self-check 339,984 probes, 0 mismatches, 0 engine failures
* findings by kind: 5,900 exception, 119 wrong_capture

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 4 | exception | `u` | `"aaaa"` | `"aa"` | `(?:(?:a(?:(?:()\|(?:\ba)*){0,3}){0,3}){2,2}){2}` | 08 |
| 4 | exception | `u` | `"aaaaaaa"` | `" "` | `(?:(?=(?:(?:(?:(?:)\|(?<!(?:))\|a*)+){0,2}){0,2})\|a)*` | 08 |
| 4 | exception | `u` | `"-\n"` | `"-aaa"` | `(?:\W(?:(?:a?\|\b\|(?:)\|a*)+){2,}){2,2}` | 08 |
| 4 | exception | `u` | `"aaaaaa"` | `""` | `(?:(?:(?:(?:a{0,1}){0,3}\|(?!()))+a){3,3}){2,2}` | 08 |
| 4 | exception | `u` | `" "` | `""` | `(?:(?:(?:()\|\|a){0,2}){0,3}){0,3}.\B` | 08 |
| 4 | exception | `u` | `""` | `"Σ"` | `(?:(?:(?:(?:(?:(?:)\|[^_\x{E9}]){0,2}){0,3}){0,2})*a\b)*` | 08 |
| 4 | exception | `u` | `" -\n"` | `""` | `(?:\W(?:(?:(?:(?:)\|(?:)\|[^\x{E0}])(?:(?:)\|\B)){0,3})*){3,}` | 08 |
| 4 | exception | `u` | `"aaaaaa"` | `""` | `(?:(?:a(?:(?:(?:a\|\B){0,2})+){0,}){3}){2,2}` | 08 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END fancy-regex 30m results -->

<!-- BEGIN fancy-regex long-10m results -->
### fancy-regex: long-10m campaign

* 273,216 patterns, 4 tables, 1 distinct findings; self-check 339,984 probes, 0 mismatches, 0 engine failures
* findings by kind: 1 wrong_capture

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 1 | wrong_capture | `u` | `"ba"` | `".a "` | `(?:(?:^(?<g1>[a-c])\|\D)\Ba)*` | 02 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END fancy-regex long-10m results -->

<!-- BEGIN fancy-regex rstop results -->
### fancy-regex: rstop campaign

* 215,360 patterns, 4 tables, 439 distinct findings
* findings by kind: 257 wrong_span, 139 wrong_capture, 28 wrong_result, 15 timeout (batch)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 3 | wrong_span | `u` | `"aa"` | `"aaϑ"` | `(?:(?:a+?)?)+` | 02 |
| 3 | wrong_capture | `u` | `"aa"` | `"aak"` | `(?:(?:a+?)*)*` | 02 |
| 3 | wrong_capture | `u` | `"aa"` | `"ϑ"` | `(?:(?:a+?)*)*` | 00 |
| 3 | wrong_span | `u` | `"aa"` | `"aak"` | `(?:(?:a+?)*)*` | 02 |
| 3 | wrong_span | `u` | `"aa"` | `"aak"` | `(?:(?:a+?)+)*` | 02 |
| 3 | wrong_span | `u` | `"aaa"` | `"а"` | `(?:(?:a+?)?)*` | 00 |
| 3 | wrong_span | `u` | `"aa"` | `"ϑ"` | `(?:(?:a+?)*)*` | 00 |
| 2 | wrong_capture | `u` | `"aa"` | `"aaϑ"` | `(?:(?:a+?)?)+` | 02 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END fancy-regex rstop results -->

<!-- BEGIN fancy-regex rthom results -->
### fancy-regex: rthom campaign

* 223,040 patterns, 4 tables, 2,008 distinct findings
* findings by kind: 1,192 wrong_span, 676 wrong_capture, 140 wrong_result

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 38 | wrong_span | `u` | `"aa"` | `"ϑ"` | `(?:\B\|a)*` | 00 |
| 31 | wrong_span | `u` | `"aa"` | `"aaϑ"` | `(?:\B\|a)*` | 02 |
| 30 | wrong_span | `u` | `"aa"` | `"ϑ"` | `(?:\B\|a)+` | 00 |
| 23 | wrong_capture | `u` | `"aa"` | `"aaϑ"` | `(?:\B\|a)*` | 02 |
| 22 | wrong_span | `u` | `"aa"` | `"ӏ"` | `(?:\B\|a)*` | 00 |
| 22 | wrong_span | `u` | `"aa"` | `"aaϑ"` | `(?:\B\|a)+` | 02 |
| 20 | wrong_span | `u` | `"aa"` | `"aaа"` | `(?:\B\|a)*` | 02 |
| 19 | wrong_capture | `u` | `"aa"` | `"ϑ"` | `(?:\B\|a)*` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END fancy-regex rthom results -->

<!-- BEGIN fancy-regex rnfa results -->
### fancy-regex: rnfa campaign

* 306,656 patterns, 5 tables, 1,373 distinct findings
* findings by kind: 786 wrong_span, 547 wrong_capture, 40 wrong_result

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 49 | wrong_span | `u` | `"aa"` | `"ϑ"` | `(?:\B\|a)*` | 00 |
| 37 | wrong_capture | `u` | `"aa"` | `"ϑ"` | `(?:\B\|a)*` | 00 |
| 36 | wrong_span | `u` | `"aa"` | `" "` | `(?:\B\|a)*` | 00 |
| 34 | wrong_capture | `u` | `"aa"` | `"aaϑ"` | `(?:\B\|a)*` | 02 |
| 34 | wrong_span | `u` | `"aa"` | `"aaϑ"` | `(?:\B\|a)*` | 02 |
| 33 | wrong_span | `u` | `"aa"` | `"ϑ"` | `(?:\B\|a)+` | 00 |
| 30 | wrong_capture | `u` | `"aa"` | `"ϑ"` | `(?:\B\|a)+` | 00 |
| 24 | wrong_span | `u` | `"aa"` | `" "` | `(?:\B\|a)+` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END fancy-regex rnfa results -->

<!-- BEGIN fancy-regex rnfa2 results -->
### fancy-regex: rnfa2 campaign

* 413,312 patterns, 6 tables, 388 distinct findings
* findings by kind: 211 wrong_span, 123 wrong_capture, 54 wrong_result

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 4 | wrong_result | `u` | `"aa"` | `"a"` | `(?:(?:\B\|a){2,}){2}` | 00 |
| 3 | wrong_span | `u` | `"aa"` | `"a"` | `(?:(?:a\|\B){2,}){2,2}` | 00 |
| 3 | wrong_capture | `u` | `"aa"` | `"ϑ"` | `(?:(?:a+?)*)*` | 00 |
| 3 | wrong_span | `u` | `"aa"` | `"ϑ"` | `(?:(?:a+?)*)*` | 00 |
| 3 | wrong_capture | `u` | `"aa"` | `"aak"` | `(?:(?:a+?)*)*` | 02 |
| 3 | wrong_span | `u` | `"aaa"` | `"а"` | `(?:(?:a+?)?)*` | 00 |
| 3 | wrong_capture | `u` | `"aa"` | `"aaϑ"` | `(?:(?:a+?)?)+` | 02 |
| 3 | wrong_span | `u` | `"aa"` | `"aak"` | `(?:(?:a+?)+)*` | 02 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END fancy-regex rnfa2 results -->

<!-- BEGIN fancy-regex rset results -->
### fancy-regex: rset campaign

* 164,512 patterns, 3 tables, 205 distinct findings
* findings by kind: 120 wrong_span, 67 wrong_capture, 18 wrong_result

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 4 | wrong_result | `u` | `"aa"` | `"k"` | `(?>(?:(?:a+?){0,})*)` | 00 |
| 4 | wrong_span | `u` | `"aa"` | `"aaϑ"` | `(?:(?:a+?)*)*` | 02 |
| 3 | wrong_capture | `u` | `"aa"` | `"ϑ"` | `(?:(?:a+?)*)?` | 00 |
| 3 | wrong_span | `u` | `"aa"` | `"ϑ"` | `(?:(?:a+?)*)?` | 00 |
| 3 | wrong_capture | `u` | `"aa"` | `"aaϑ"` | `(?:(?:a+?)*)*` | 02 |
| 3 | wrong_span | `u` | `"aa"` | `"ϑ"` | `(?:(?:a+?)*)*` | 00 |
| 2 | wrong_span | `imsu` | `"àKſékΣk"` | `"àKéàkΣk"` | `(?:(?:(?:[^\p{Lu}--s]\|\P{So}(?=(?:.\|[ \-]$)()).)+?)*)?` | 02 |
| 2 | wrong_span | `imsu` | `"àKſékΣk"` | `"àKéàkΣk"` | `(?:(?:(?:[^K&&[a-z]][A-Z]+)+?)*)*` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END fancy-regex rset results -->

<!-- BEGIN fancy-regex rglob results -->
### fancy-regex: rglob campaign

* 97,792 patterns, 2 tables, 193 distinct findings
* findings by kind: 147 wrong_span, 40 wrong_capture, 6 wrong_result

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 8 | wrong_span | `u` | `"aa"` | `"aaϑ"` | `(?:(?:a+?)*)*` | 02 |
| 4 | wrong_span | `u` | `"aa"` | `"aaа"` | `(?:(?:a+?)+)?` | 02 |
| 4 | wrong_span | `u` | `"aa"` | `"а"` | `(?:(?:a+?)+)?` | 00 |
| 4 | wrong_span | `u` | `"aa"` | `"ϑ"` | `(?:(?:a+?)*)?` | 00 |
| 4 | wrong_span | `u` | `"aa"` | `"aaϑ"` | `(?:(?:a+?)+)?` | 02 |
| 4 | wrong_span | `u` | `"aa"` | `"ϑ"` | `(?:(?:a+?)+)?` | 00 |
| 4 | wrong_span | `u` | `"aa"` | `"aaϑ"` | `(?:(?:a+?)+)*` | 02 |
| 3 | wrong_capture | `u` | `"aa"` | `"aaϑ"` | `(?:(?:a+?)*)*` | 02 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END fancy-regex rglob results -->

<!-- BEGIN fancy-regex r10 results -->
### fancy-regex: r10 campaign

* 1,660,416 patterns, 18 tables, 152 distinct findings
* findings by kind: 141 wrong_capture, 6 wrong_result, 5 wrong_span

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 2 | wrong_result | `iu` | `"sſſS"` | `""` | `([A-Z]+)(?:\1)` | 00 |
| 2 | wrong_result | `iu` | `"sſſS"` | `"a"` | `(\S*)(?:\1)` | 00 |
| 1 | wrong_capture | `u` | `"aaaaaaaa"` | `"aaaaaaaaa"` | `(?:(?:(^)a\|a)aa\Ba)+` | 02 |
| 1 | wrong_capture | `u` | `"a\naaaaaa"` | `"a\naaaaaaa"` | `(?:(?:(?!)\|a)(?:(\s)\|a))*` | 02 |
| 1 | wrong_capture | `u` | `"aaaaaaaθ"` | `"aaa0a"` | `(?:a\B(?:\p{Nd}\|[\x{430}\x{3B8}]\|(?<g1>a))){0,}` | 02 |
| 1 | wrong_capture | `u` | `"a\naaaaaa"` | `"a\naaa"` | `(?:a(?>a\|(\p{Cc})))+` | 02 |
| 1 | wrong_capture | `u` | `"_a"` | `"ſ"` | `(?>(\P{Ll})\|a){0,}` | 00 |
| 1 | wrong_capture | `u` | `"aaa0aaaa"` | `"a"` | `(?:a(?=)(?:a\|(?<g1>\S)))*` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END fancy-regex r10 results -->

<!-- BEGIN fancy-regex r10b results -->
### fancy-regex: r10b campaign

* 1,854,272 patterns, 20 tables, 436 distinct findings
* findings by kind: 243 wrong_span, 150 wrong_capture, 42 wrong_result, 1 timeout (batch)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 4 | wrong_span | `u` | `"aa"` | `"aaſ"` | `(?:(?:a+?)+)*` | 02 |
| 4 | wrong_span | `u` | `"aa"` | `"aaſ"` | `(?:(?:a+?)+)?` | 02 |
| 4 | wrong_capture | `u` | `"aa"` | `"aaſ"` | `(?:(?:a+?)+)*` | 02 |
| 4 | wrong_result | `u` | `"aa"` | `"a"` | `(?:(?:\B\|a){2,}){2}` | 00 |
| 4 | wrong_capture | `u` | `"aa"` | `"_"` | `(?:(?:a+?)+)*` | 00 |
| 4 | wrong_capture | `u` | `"aa"` | `"aaſ"` | `(?:(?:a+?)+)?` | 02 |
| 4 | wrong_span | `u` | `"aa"` | `"_"` | `(?:(?:a+?)+)*` | 00 |
| 3 | wrong_span | `u` | `"aaaaaaaa"` | `"aaaaa"` | `(?x:(?:(?:(?:a a)+?)+)?)` | 03 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END fancy-regex r10b results -->

<!-- BEGIN fancy-regex r2h results -->
### fancy-regex: r2h campaign

* 539,424 patterns, 7 tables, 655 distinct findings; self-check 14,322,400 probes, 0 mismatches, 76 engine failures
* findings by kind: 485 wrong_span, 130 wrong_capture, 40 wrong_result

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 6 | wrong_span | `u` | `"aa"` | `"aaϑ"` | `(?:(?:a+?)*)*` | 02 |
| 5 | wrong_span | `u` | `"aa"` | `"ϑ"` | `(?:(?:a+?)*)*` | 00 |
| 4 | wrong_span | `imsu` | `"àKſékΣk"` | `"àKéàkΣk"` | `(?:[^K~~K](?:(?:(?:[^\u{1F600}\u{E0}]{1,}?)?)*\|[ \u017F](?:^[\u{391}-\u03A9])+\z))?` | 02 |
| 4 | wrong_span | `u` | `"aa"` | `"а"` | `(?:(?:a+?)+)?` | 00 |
| 4 | wrong_span | `u` | `"aa"` | `"aas"` | `(?:(?:a+?)*){0,}` | 02 |
| 4 | wrong_span | `u` | `"aa"` | `"а"` | `(?:(?:a+?)?){0,}` | 00 |
| 4 | wrong_span | `u` | `"aa"` | `"aaϑ"` | `(?:(?:a+?)+)?` | 02 |
| 4 | wrong_result | `u` | `"aa"` | `"k"` | `(?>(?:(?:a+?){0,})*)` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END fancy-regex r2h results -->
<!-- BEGIN fancy-regex r2h triage -->
### fancy-regex: r2h (2-hour) campaign triage

fancy-regex 0.19.2.

* No new bugs. IRX-FANCY-2 (lazy loops inside loops, e.g. `(?:(?:a+?)*)*` on `"aa"`), about 470 findings; IRX-FANCY-3 (unbounded inner repeat whose first iteration in a later outer round matches empty), including a lookbehind variant: `^(?:(?:\D|(?<=\W)){2,}){2}$` fails on `" a"` (Perl matches).
* Known model gap (not modelled): inside a pattern that runs on fancy-regex's VM (lookarounds, atomic groups, `\b`/`\B`/`\>`), plain subexpressions are still handed to the regex crate, so their loops follow the regex crate's empty-iteration rule: `(?>(?:a|()|[^σ-])*)` on `"as"` is `[0,2)` (Perl `[0,1)`). About 100 findings.
* 76 self-check engine failures: batch deadline exceeded under load.
<!-- END fancy-regex r2h triage -->
