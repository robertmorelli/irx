# RE2 (ASan/UBSan)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py re2-asan`.
The [`re2`](../re2) target with AddressSanitizer and UndefinedBehaviorSanitizer: RE2 and abseil built from source (`tools/build_asan.sh`). A memory error or undefined behavior aborts the host and is recorded as a crash, even when the answer would have been right. Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN re2-asan r10 results -->
### RE2 (ASan/UBSan): r10 campaign

* 87,552 patterns, 2 tables, 18 distinct findings
* findings by kind: 18 timeout (batch)

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END re2-asan r10 results -->

<!-- BEGIN re2-asan r2h results -->
### RE2 (ASan/UBSan): r2h campaign

* 978,848 patterns, 11 tables, 953 distinct findings; self-check 3,473,184 probes, 0 mismatches, 0 engine failures
* findings by kind: 565 wrong_span, 388 timeout (batch)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 103 | wrong_span | `u` | `""` | `"aaaa "` | `\B` | 03 |
| 77 | wrong_span | `u` | `""` | `"aaa "` | `\B` | 03 |
| 23 | wrong_span | `u` | `""` | `"aaK"` | `\B` | 03 |
| 23 | wrong_span | `u` | `""` | `"aaaϑ"` | `\B` | 03 |
| 22 | wrong_span | `u` | `""` | `"aaaK"` | `\B` | 03 |
| 19 | wrong_span | `u` | `""` | `"aaſ"` | `\B` | 03 |
| 17 | wrong_span | `u` | `""` | `"aaϑ"` | `\B` | 03 |
| 12 | wrong_span | `u` | `""` | `"aaaaſ"` | `\B` | 03 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END re2-asan r2h results -->
<!-- BEGIN re2-asan r2h triage -->
### re2-asan: r2h (2-hour) campaign triage

RE2 (ASan/UBSan build).

* No new bugs and no ASan/UBSan reports; self-check clean. All 565 wrong spans are IRX-RE2-2 (`\B` matches between the bytes of a multibyte character; the span lands inside ϑ). The 388 timeouts are batch timeouts under ASan's slowdown.
<!-- END re2-asan r2h triage -->
