# Hermes (jsvu)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py hermes`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN hermes results -->
## Hermes campaign results

10-minute campaign, 8 cores, edit-distance-5 A/R pairs, via `tools/bridge.py`; `v` flag sets excluded
(unsupported); no self-check.

* 595,232 patterns over 7 tables.
* 1,704 wrong results: IRX-HERMES-1, e.g. `/^(?:(?:(?:\W+){1,1})*\s)$/` misses `"\u2028\n"`.
* 26 exceptions: IRX-HERMES-2 (`RangeError: Maximum regex stack depth reached` on 1–2 character inputs).
* 2,236 timeouts (not triaged).

Counts are distinct findings; one bug produces many distinct regexes. Shapes were checked on the minimized subset triaged during the campaign, and representatives were confirmed against d8 15.5 and the relation model.
<!-- END hermes results -->

<!-- BEGIN hermes 1m results -->
### hermes: 1-minute smoke campaign

* 57,344 patterns, 2 tables, 224 distinct findings
* findings by kind: 224 timeout (batch)

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END hermes 1m results -->

<!-- BEGIN hermes 10m results -->
### Hermes (jsvu): 10m campaign

* 611,776 patterns, 8 tables, 2,236 distinct findings
* findings by kind: 2,175 timeout (batch), 55 exception, 6 wrong_result

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 2 | exception | `` | `""` | `"a"` | `(?:a?)*?^` | 08 |
| 2 | exception | `` | `"a"` | `""` | `(?:(?:a?)+)*a` | 08 |
| 2 | exception | `` | `"a"` | `""` | `(?:(?:a\|(?:))?)*a` | 08 |
| 2 | exception | `` | `"a"` | `"."` | `(?:[\u00E0.]\|(?:))*?a` | 08 |
| 2 | exception | `` | `"a"` | `""` | `(?:(?:a\|(?:))?){0,2}a` | 08 |
| 2 | exception | `` | `"a"` | `" "` | `(?:[^A.]\|(?:))*?a` | 08 |
| 2 | exception | `` | `""` | `"aa"` | `(?:^(?:a\|(?:)))*?` | 08 |
| 2 | exception | `` | `"a"` | `""` | `(?:(?:a\|(?:))*){0,}a` | 08 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END hermes 10m results -->

<!-- BEGIN hermes 10m triage -->
### hermes: 10-minute campaign triage

* New: **IRX-HERMES-3** (`(?:(?:a+){1}){2}` misses `"aa"`) and **IRX-HERMES-4** (`a(?<=x|^a)` misses `"a"`),
  from the 6 wrong results.
* The 55 exceptions are IRX-HERMES-2 (`Maximum regex stack depth reached` on tiny inputs such as `(?:a|(?:))*?`).
* The 2,175 timeouts are genuine: timing one batch case by case found 5 cases over 5 s and 7 more over 2 s, all
  on an 8-character subject with nested nullable loops. Same family as IRX-HERMES-2.
<!-- END hermes 10m triage -->

<!-- BEGIN hermes 5m results -->
### Hermes (jsvu): 5m campaign

* 144,032 patterns, 3 tables, 951 distinct findings
* findings by kind: 789 timeout (batch), 152 wrong_span, 10 exception

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 3 | wrong_span | `` | `"aa"` | `""` | `(?:(?:a+){1,1}){2,2}` | 00 |
| 3 | wrong_span | `` | `"aa"` | `""` | `(?:(?:a{1,}){1,1}){2,}` | 00 |
| 3 | wrong_span | `` | `"aa"` | `""` | `(?:(?:a{1,})+){2}` | 00 |
| 2 | wrong_span | `` | `"aa"` | `""` | `(?:(?:a{1,}){1,1}){2,2}` | 00 |
| 2 | wrong_span | `` | `"aa"` | `""` | `(?:(?:aa*){1,1}){2,2}` | 00 |
| 2 | wrong_span | `` | `"aa"` | `""` | `(?:(?:a+){1,1}){0,2}a` | 00 |
| 1 | wrong_span | `` | `"aa"` | `""` | `(?:(?:a{1,}){1,1}){0,2}a` | 00 |
| 1 | wrong_span | `` | `" aa"` | `""` | `\W(?:(?:a+){1,1}){2,}` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END hermes 5m results -->

<!-- BEGIN hermes 30m results -->
### Hermes (jsvu): 30m campaign

* 14,592 patterns, 2 tables, 103 distinct findings
* findings by kind: 95 exception, 4 wrong_result, 2 wrong_span, 2 wrong_capture

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 2 | wrong_result | `` | `"aa"` | `""` | `(?:(?:a{1,}){1,1}){2,2}` | 00 |
| 2 | exception | `` | `""` | `"aß"` | `(?:a\|())+?` | 08 |
| 2 | wrong_result | `` | `"aaaa"` | `""` | `(?:(?:a{3,}?)+)+` | 00 |
| 1 | wrong_span | `` | `""` | `"aa"` | `(?:(?:(?:a+){1,1})+\|())\B` | 03 |
| 1 | exception | `` | `""` | `"aß"` | `(?:a\|(?:)())*?` | 08 |
| 1 | exception | `` | `""` | `"aß"` | `(?:a\|(?:){2})+?` | 08 |
| 1 | wrong_capture | `` | `""` | `"aa"` | `(?:(?:(?:a+){1,1})+\|())\B` | 03 |
| 1 | exception | `` | `""` | `"a0"` | `(?:a\|(?:(?:)\|)())+?` | 08 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END hermes 30m results -->
