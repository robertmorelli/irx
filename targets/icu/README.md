# ICU NSRegularExpression

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py icu`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN icu 1m results -->
### icu: 1-minute smoke campaign

* 59,392 patterns, 2 tables, 232 distinct findings; self-check 281,792 probes, 3,280 mismatches, 0 engine failures
* findings by kind: 232 timeout (batch), 199 selfcheck_mismatch (selfcheck)

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END icu 1m results -->

<!-- BEGIN icu 10m results -->
### ICU NSRegularExpression: 10m campaign

* 599,840 patterns, 7 tables, 2,342 distinct findings; self-check 339,984 probes, 0 mismatches, 0 engine failures
* findings by kind: 2,342 timeout (batch)

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END icu 10m results -->

<!-- BEGIN icu 10m triage -->
### icu: 10-minute campaign triage

* New: **IRX-ICU-1**, an infinite loop: a lazy unbounded loop whose body matches empty, followed by a failure
  (`a(?:)*?b` on `"ac"`). The fuzzer generates this shape so often that every batch timed out and the campaign
  executed **0** cases, so this run says nothing else about ICU. Rerun after excluding lazy loops over nullable
  bodies from the `icu` dialect, or with a per-case watchdog.
* Self-check clean.
<!-- END icu 10m triage -->

<!-- BEGIN icu 5m results -->
### ICU NSRegularExpression: 5m campaign

* 150,176 patterns, 3 tables, 882 distinct findings; self-check 339,984 probes, 0 mismatches, 0 engine failures
* findings by kind: 882 timeout (batch)

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END icu 5m results -->

<!-- BEGIN icu 30m results -->
### ICU NSRegularExpression: 30m campaign

* 898,304 patterns, 10 tables, 36,284 distinct findings; self-check 339,984 probes, 0 mismatches, 0 engine failures
* findings by kind: 28,431 wrong_result, 3,711 wrong_span, 3,566 wrong_capture, 576 syntax_error

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 39 | wrong_result | `u` | `"a"` | `"ß"` | `(?:\|a)*?` | 00 |
| 35 | wrong_result | `u` | `"a"` | `"ß"` | `(?:()\|a)*?` | 00 |
| 29 | wrong_result | `u` | `"a"` | `"ß"` | `(?:a*?)*?` | 00 |
| 26 | wrong_result | `u` | `"a"` | `"ß"` | `(?:(?:)\|a)+?` | 00 |
| 26 | wrong_result | `u` | `"a"` | `"s"` | `(?:(?:)\|a)*?` | 00 |
| 25 | wrong_result | `u` | `"a"` | `"k"` | `(?:()\|a)*?` | 00 |
| 25 | wrong_result | `su` | `"a"` | `"a "` | `.+\b` | 03 |
| 24 | wrong_result | `u` | `"a"` | `"k"` | `(?:(?:)\|a)*?` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END icu 30m results -->

<!-- BEGIN icu long-10m results -->
### ICU NSRegularExpression: long-10m campaign

* 127,648 patterns, 3 tables, 2,141 distinct findings; self-check 339,984 probes, 0 mismatches, 0 engine failures
* findings by kind: 1,439 long_result, 343 wrong_span, 329 wrong_capture, 30 syntax_error

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 57 | long_result | `u` | `"- kß "` | `"-K0ß"` | `(?:\|\D)*?` | 00 |
| 49 | long_result | `u` | `"- kß "` | `"-K0ß"` | `(?:()\|\D)*?` | 00 |
| 48 | long_result | `u` | `"- kß "` | `"-K0ß"` | `(?:(?:)\|\D)*?` | 00 |
| 28 | long_result | `u` | `"- kß "` | `"-K0ß"` | `(?:(?:)\|\D)+?` | 00 |
| 25 | long_result | `u` | `"- kß "` | `"-K0ß"` | `(?:()\|\D)+?` | 00 |
| 24 | long_result | `u` | `"- kß "` | `"-K0ß"` | `(?:\|\D)+?` | 00 |
| 19 | long_result | `u` | `"- kß "` | `"-K0ß"` | `(?:\D??)*?` | 00 |
| 18 | long_result | `u` | `"- kß "` | `"-K0ß"` | `(?:\D??)+?` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END icu long-10m results -->

<!-- BEGIN icu r10 results -->
### ICU NSRegularExpression: r10 campaign

* 387,168 patterns, 5 tables, 8,244 distinct findings
* findings by kind: 4,000 wrong_result, 1,982 wrong_span, 1,906 wrong_capture, 356 syntax_error

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 29 | wrong_result | `u` | `"a"` | `"ϑ"` | `(?:\|a)*?` | 00 |
| 17 | wrong_result | `u` | `"a"` | `"ϑ"` | `(?:a*?)*?` | 00 |
| 17 | wrong_result | `u` | `"a"` | `"ϑ"` | `(?:(?:)\|a)*?` | 00 |
| 16 | wrong_result | `u` | `"a"` | `"ϑ"` | `(?:()\|a)*?` | 00 |
| 15 | wrong_result | `u` | `"a"` | `"ϑ"` | `(?:\|a)+?` | 00 |
| 14 | wrong_result | `u` | `"a"` | `"ӏ"` | `(?:()\|a)*?` | 00 |
| 14 | syntax_error | `u` | `""` | `"a"` | `(?<=(?=(?:)*))` | 04 |
| 13 | wrong_result | `u` | `"a"` | `"а"` | `(?:()\|a)+?` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END icu r10 results -->

<!-- BEGIN icu r2h results -->
### ICU NSRegularExpression: r2h campaign

* 4,926,752 patterns, 51 tables, 8,000 distinct findings; self-check 4,797,600 probes, 0 mismatches, 0 engine failures
* findings by kind: 4,000 wrong_result, 2,000 wrong_span, 2,000 wrong_capture

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 195 | wrong_result | `u` | `"a"` | `"ϑ"` | `(?:\|a)*?` | 00 |
| 176 | wrong_result | `u` | `"a"` | `"ϑ"` | `(?:()\|a)*?` | 00 |
| 170 | wrong_result | `u` | `"a"` | `"ϑ"` | `(?:(?:)\|a)*?` | 00 |
| 122 | wrong_result | `u` | `"a"` | `"ϑ"` | `(?:a*?)*?` | 00 |
| 117 | wrong_capture | `u` | `"a"` | `""` | `a\b\b` | 00 |
| 114 | wrong_result | `u` | `"a"` | `"а"` | `(?:()\|a)*?` | 00 |
| 106 | wrong_result | `u` | `"a"` | `"а"` | `(?:\|a)*?` | 00 |
| 105 | wrong_span | `u` | `"a"` | `""` | `a\b\b` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END icu r2h results -->
<!-- BEGIN icu r2h triage -->
### icu: r2h (2-hour) campaign triage

macOS 27.0.1 `NSRegularExpression` (system `libicucore`), with the ICU model fixes from the icu-c-asan run.

* No new IDs. IRX-ICU-1 widened: lazy loops whose body starts with an empty branch (`^(?:(?:|a)*?)$` on `"a"`) hit the ICU4C time limit, and `NSRegularExpression` reports no match; about 6,700 findings.
* Known: IRX-ICU-4/-5 (word boundaries; fixed in ICU4C 78.3, still in the system `libicucore`, e.g. `a(?:\B|\b)` on `"a"`), about 1,100; IRX-ICU-6 (possessive empty loops, `(?:)*+`), about 70; IRX-ICU-7 (one-member ligature sets under `(?i)`), 68; IRX-ICU-3 (counted zero-width alternation in a lookbehind), about 50.
* Self-check clean.
<!-- END icu r2h triage -->
