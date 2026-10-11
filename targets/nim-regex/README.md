# nim-regex

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py nim-regex`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN nim-regex 1m results -->
### nim-regex: 1-minute smoke campaign

* 406,144 patterns, 6 tables, 13,122 distinct findings; self-check 281,792 probes, 18,100 mismatches, 0 engine failures
* findings by kind: 6,128 syntax_error, 4,680 wrong_result, 2,170 exception, 200 selfcheck_mismatch (selfcheck), 144 timeout (batch)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 37 | syntax_error | `u` | `"a"` | `""` | `(?<g0>a)` | 04 |
| 34 | syntax_error | `u` | `""` | `"a"` | `(?<g0>(?:))` | 04 |
| 16 | syntax_error | `u` | `"a"` | `""` | `(?<g0>(?:))a` | 04 |
| 14 | syntax_error | `u` | `"a"` | `""` | `a(?<g0>(?:))` | 04 |
| 6 | wrong_result | `u` | `"a"` | `""` | `a(?:(?<=(?:))){0,2}` | 00 |
| 4 | wrong_result | `u` | `"a"` | `""` | `a(?:(?!(?:))){0,2}` | 00 |
| 2 | wrong_result | `u` | `"aa"` | `""` | `a(?:(?=(?:))a){1,}` | 00 |
| 2 | wrong_result | `u` | `"aaaaaaaa"` | `"aaaaaa"` | `(?:(?:(?<!(?:))\|aa){2})*` | 33 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END nim-regex 1m results -->

<!-- BEGIN nim-regex 10m results -->
### nim-regex: 10m campaign

* 2,148,128 patterns, 23 tables, 28,255 distinct findings; self-check 281,792 probes, 0 mismatches, 0 engine failures
* findings by kind: 18,228 wrong_result, 8,333 exception, 1,682 timeout (batch), 12 crash (batch)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 42 | wrong_result | `u` | `""` | `"a"` | `(?:)\|(?:(?=(?:))){0,2}` | 03 |
| 41 | wrong_result | `u` | `""` | `"a"` | `(?:)\|(?:(?<=(?:))){0,2}` | 03 |
| 39 | wrong_result | `u` | `""` | `"a"` | `(?:)\|(?:(?!(?:))){0,2}` | 03 |
| 38 | wrong_result | `u` | `""` | `"a"` | `(?:)\|(?:(?<!(?:))){0,2}` | 03 |
| 31 | wrong_result | `u` | `""` | `"a"` | `(?:)\|(?:(?!(?:))){0,2}` | 33 |
| 28 | wrong_result | `u` | `"a"` | `""` | `(?:(?!(?:))){1,2}\|a` | 00 |
| 28 | wrong_result | `u` | `""` | `"a"` | `(?:)\|(?:(?<!(?:))){0,2}` | 33 |
| 28 | wrong_result | `u` | `""` | `"a"` | `(?:)\|(?:(?=(?:))){0,2}` | 33 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END nim-regex 10m results -->

<!-- BEGIN nim-regex 10m triage -->
### nim-regex: 10-minute campaign triage

* Nothing new. All 912 minimized shapes have a lookaround inside a quantifier, NIM-1 (wrong results, and the 8,333
  exceptions such as `(?:(?=(?:))|(?=(?:))){0,}`).
* The 12 segfaults are NIM-3: an optional followed by a star of a nullable atom, e.g. `a?(?:^)*b`, the same
  shape as `a?(?:b?)*c`.
* 1,682 timeouts, not investigated; NIM-4 (exponential compile of counted empty alternatives) is the likely cause.
* Self-check clean.
<!-- END nim-regex 10m triage -->

<!-- BEGIN nim-regex 5m results -->
### nim-regex: 5m campaign

* 592,672 patterns, 7 tables, 44,519 distinct findings; self-check 281,792 probes, 0 mismatches, 0 engine failures
* findings by kind: 25,160 exception, 14,358 wrong_result, 4,294 wrong_span, 465 timeout (batch), 238 syntax_error, 4 crash (batch)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 6 | exception | `u` | `""` | `"a"` | `(?:(?!(?:))){0,}` | 08 |
| 6 | exception | `u` | `""` | `"a"` | `(?:(?!(?:))){0,1}` | 08 |
| 5 | exception | `u` | `""` | `"a"` | `(?:(?!())){0,}` | 08 |
| 5 | exception | `u` | `""` | `"a"` | `(?:(?<=(?:))){0,1}` | 08 |
| 4 | exception | `u` | `""` | `"a"` | `(?:(?=())){0,}` | 08 |
| 4 | exception | `u` | `""` | `"a"` | `(?:(?<!())){0,}` | 08 |
| 3 | exception | `u` | `""` | `"a"` | `(?:(?=(?:))){0,}` | 08 |
| 3 | exception | `u` | `""` | `"a"` | `(?:(?<=())){0,}` | 08 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END nim-regex 5m results -->

<!-- BEGIN nim-regex 30m results -->
### nim-regex: 30m campaign

* 3,057,856 patterns, 32 tables, 211,988 distinct findings; self-check 281,792 probes, 0 mismatches, 0 engine failures
* findings by kind: 146,509 exception, 37,637 wrong_result, 11,287 wrong_span, 11,156 wrong_capture, 4,063 timeout (batch), 1,256 syntax_error, 80 crash (batch)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 108 | exception | `u` | `""` | `"a"` | `(?:(?=(?:))){0,}` | 08 |
| 96 | exception | `u` | `""` | `"a"` | `(?:(?=())){0,}` | 08 |
| 93 | exception | `u` | `""` | `"a"` | `(?:(?<!(?:))){0,}` | 08 |
| 92 | exception | `u` | `""` | `"a"` | `(?:(?<!())){0,}` | 08 |
| 91 | exception | `u` | `""` | `"a"` | `(?:(?!(?:))){0,}` | 08 |
| 90 | exception | `u` | `""` | `"a"` | `(?:(?!())){0,}` | 08 |
| 86 | exception | `u` | `""` | `"a"` | `(?:(?<!(?:))){0,1}` | 08 |
| 85 | exception | `u` | `""` | `"a"` | `(?:(?<!())){0,1}` | 08 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END nim-regex 30m results -->
