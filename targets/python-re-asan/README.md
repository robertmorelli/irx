# Python re, CPython 3.14 (ASan/UBSan)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py python-re-asan`.
The [`python-re`](../python-re) target on CPython 3.14.8 built with `--with-address-sanitizer --with-undefined-behavior-sanitizer` (`tools/build_asan_big.sh python`, into `vendor/asan/python`), so sre (the C engine behind `re`) runs instrumented. Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN python-re-asan r10 results -->
### Python re, CPython 3.14 (ASan/UBSan): r10 campaign

* 143,008 patterns, 3 tables, 108 distinct findings
* findings by kind: 106 timeout (batch), 2 wrong_result

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 1 | wrong_result | `u` | `"aaaa"` | `"а"` | `(?x:(?:(?:(?:)? (?:a\|())\|(?>(?:)))+)+ ^ a*)` | 01 |
| 1 | wrong_result | `u` | `"aaaaa"` | `"ϑ"` | `(?x:(?:(?:a?\|(?>(?:)))+)+ ^ a*)` | 11 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END python-re-asan r10 results -->

<!-- BEGIN python-re-asan r2h results -->
### Python re, CPython 3.14 (ASan/UBSan): r2h campaign

* 1,128,160 patterns, 13 tables, 1,725 distinct findings; self-check 3,353,376 probes, 0 mismatches, 0 engine failures
* findings by kind: 1,651 timeout (batch), 30 wrong_result, 25 wrong_span, 19 wrong_capture

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 6 | wrong_result | `u` | `"aa"` | `""` | `(?:a{1,}){2,}+` | 00 |
| 4 | wrong_result | `u` | `"aa"` | `""` | `(?m:a{1,}){2}+` | 00 |
| 3 | wrong_capture | `u` | `"aa"` | `""` | `(?:a{1,}){2,}+` | 00 |
| 3 | wrong_span | `u` | `"aaaaa"` | `""` | `(?P<g1>(?:a\|\b)a){3}+` | 00 |
| 3 | wrong_span | `u` | `"aa"` | `""` | `(?:a{1,}){2,}+` | 00 |
| 2 | wrong_result | `u` | `"aa"` | `""` | `(?:a{1,}){2,2}+` | 00 |
| 2 | wrong_result | `u` | `"aaaaa"` | `""` | `(?P<g1>(?:a\|\b)a){3}+` | 00 |
| 2 | wrong_result | `u` | `"aa"` | `""` | `(a{1,}){2,2}+` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END python-re-asan r2h results -->
<!-- BEGIN python-re-asan r2h triage -->
### python-re-asan: r2h (2-hour) campaign triage

CPython 3.14.8 `re` (ASan/UBSan build).

* No new bugs and no ASan/UBSan reports; self-check clean. All 74 wrong answers are IRX-PYRE-1 (possessive counted repeats do not backtrack inside: `(?:a+){2,}+`, `(?P<g1>(?:a|\b)a){3}+` on `aaaaa`). The 1,651 timeouts are batch timeouts on deeply nested loops under ASan's slowdown.
<!-- END python-re-asan r2h triage -->
