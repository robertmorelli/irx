# C++ std::regex, libc++ (ASan/UBSan)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py cpp-asan`.
The [`cpp-regex`](../cpp-regex) host built with AddressSanitizer and UndefinedBehaviorSanitizer (`-fsanitize=address,undefined`), with the engine itself instrumented (`std::regex` is header templates, so the host build instruments it). A memory error or undefined behavior aborts the host and is recorded as a crash, even when the answer would have been right. Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN cpp-asan r10 results -->
### C++ std::regex, libc++ (ASan/UBSan): r10 campaign

* 10,211,776 patterns, 104 tables, 9,748 distinct findings
* findings by kind: 4,000 wrong_result, 2,000 wrong_capture, 2,000 wrong_span, 1,748 syntax_error

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 104 | syntax_error | `` | `""` | `"a"` | `((?:))\|(?!(?:\1))` | 04 |
| 98 | wrong_result | `` | `"a"` | `""` | `a(?=\b)` | 00 |
| 96 | wrong_result | `m` | `"\na"` | `""` | `\s^a` | 00 |
| 96 | wrong_result | `m` | `"\na"` | `""` | `\x{A}^a` | 00 |
| 93 | wrong_result | `m` | `"\na"` | `""` | `\D^a` | 00 |
| 84 | syntax_error | `` | `""` | `"a"` | `()\|(?!(?:\1))` | 04 |
| 83 | wrong_result | `m` | `"\na"` | `""` | `\W^a` | 00 |
| 80 | syntax_error | `` | `""` | `"a"` | `()(?=(?:\1))` | 04 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END cpp-asan r10 results -->

<!-- BEGIN cpp-asan r2h results -->
### C++ std::regex, libc++ (ASan/UBSan): r2h campaign

* 134,901,024 patterns, 1351 tables, 8,000 distinct findings; self-check 74,220 probes, 188 mismatches, 0 engine failures
* findings by kind: 4,000 wrong_result, 2,000 wrong_span, 2,000 wrong_capture, 20 selfcheck_mismatch (selfcheck)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 222 | wrong_result | `m` | `"\na"` | `""` | `\W^a` | 00 |
| 210 | wrong_result | `m` | `"\na"` | `""` | `\x{A}^a` | 00 |
| 202 | wrong_result | `m` | `"\na"` | `""` | `\D^a` | 00 |
| 182 | wrong_result | `m` | `"\na"` | `""` | `\s^a` | 00 |
| 100 | wrong_result | `` | `"a"` | `""` | `a(?=\b)` | 00 |
| 91 | wrong_span | `m` | `"\na"` | `""` | `\D^a` | 00 |
| 91 | wrong_capture | `m` | `"\na"` | `""` | `\D^a` | 00 |
| 89 | wrong_capture | `m` | `"\na"` | `""` | `\x{A}^a` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END cpp-asan r2h results -->
<!-- BEGIN cpp-asan r2h triage -->
### cpp-asan: r2h (2-hour) campaign triage

* No new bugs and no ASan/UBSan reports. Every finding is a known libc++ bug: IRX-LIBCXX-1 (`^` after a newline under multiline, e.g. `\W^a` on `"\na"`) about 6,090; IRX-LIBCXX-2 (`\b`/`\B` inside a lookaround, e.g. `a(?=\b)`) about 1,570; IRX-LIBCXX-3 (word boundary at the end of the subject, e.g. `\B|aa` on `"a"` gives `[1,1)`, `(?:\b|a)$` on `"A"` no match) about 350.
* The 188 self-check mismatches are IRX-LIBCXX-1 (`[^]{1}^[^]*` under multiline).
<!-- END cpp-asan r2h triage -->
