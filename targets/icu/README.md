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
