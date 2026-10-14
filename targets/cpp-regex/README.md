# C++ std::regex (libc++)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py cpp-regex`.
The standard library's `std::regex` (libc++, shipped with Xcode) with the ECMAScript grammar, over code points
(`std::wregex`). Only the `i` and `m` flags exist, there is no lookbehind, `\p{…}` or inline modifier, and the
pool stays ASCII (dialect `cpp`). Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN cpp-regex r10 results -->
### C++ std::regex (libc++): r10 campaign

* 20,701,024 patterns, 209 tables, 8,000 distinct findings
* findings by kind: 4,000 wrong_result, 2,000 wrong_span, 2,000 wrong_capture

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 222 | wrong_result | `m` | `"\na"` | `""` | `\W^a` | 00 |
| 210 | wrong_result | `m` | `"\na"` | `""` | `\x{A}^a` | 00 |
| 202 | wrong_result | `m` | `"\na"` | `""` | `\D^a` | 00 |
| 183 | wrong_result | `m` | `"\na"` | `""` | `\s^a` | 00 |
| 100 | wrong_result | `` | `"a"` | `""` | `a(?=\b)` | 00 |
| 91 | wrong_capture | `m` | `"\na"` | `""` | `\D^a` | 00 |
| 91 | wrong_span | `m` | `"\na"` | `""` | `\D^a` | 00 |
| 89 | wrong_capture | `m` | `"\na"` | `""` | `\x{A}^a` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END cpp-regex r10 results -->

<!-- BEGIN cpp-regex r2h results -->
### C++ std::regex (libc++): r2h campaign

* 199,501,024 patterns, 1997 tables, 8,000 distinct findings; self-check 74,220 probes, 188 mismatches, 0 engine failures
* findings by kind: 4,000 wrong_result, 2,000 wrong_span, 2,000 wrong_capture, 20 selfcheck_mismatch (selfcheck)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 222 | wrong_result | `m` | `"\na"` | `""` | `\W^a` | 00 |
| 210 | wrong_result | `m` | `"\na"` | `""` | `\x{A}^a` | 00 |
| 202 | wrong_result | `m` | `"\na"` | `""` | `\D^a` | 00 |
| 182 | wrong_result | `m` | `"\na"` | `""` | `\s^a` | 00 |
| 100 | wrong_result | `` | `"a"` | `""` | `a(?=\b)` | 00 |
| 91 | wrong_capture | `m` | `"\na"` | `""` | `\D^a` | 00 |
| 91 | wrong_span | `m` | `"\na"` | `""` | `\D^a` | 00 |
| 89 | wrong_capture | `m` | `"\na"` | `""` | `\x{A}^a` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END cpp-regex r2h results -->
<!-- BEGIN cpp-regex r2h triage -->
### cpp-regex: r2h (2-hour) campaign triage

* No new bugs. Same set as `cpp-asan`: IRX-LIBCXX-1 (`^` after a newline under multiline) about 6,090 findings, IRX-LIBCXX-2 (`\b`/`\B` inside a lookaround) about 1,570, IRX-LIBCXX-3 (word boundary at the end of the subject) about 350; the 188 self-check mismatches are IRX-LIBCXX-1 (`[^]{1}^[^]*`).
<!-- END cpp-regex r2h triage -->
