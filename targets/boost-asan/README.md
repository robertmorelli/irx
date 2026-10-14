# Boost.Regex 1.92 (ASan/UBSan)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py boost-asan`.
The [`boost-regex`](../boost-regex) host built with AddressSanitizer and UndefinedBehaviorSanitizer (`-fsanitize=address,undefined`), with the engine itself instrumented (Boost.Regex is header-only, so the host build instruments it). A memory error or undefined behavior aborts the host and is recorded as a crash, even when the answer would have been right. Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN boost-asan r10 results -->
### Boost.Regex 1.92 (ASan/UBSan): r10 campaign

* 15,059,392 patterns, 152 tables, 2,005 distinct findings
* findings by kind: 1,812 wrong_capture, 191 wrong_span, 2 wrong_result

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 16 | wrong_capture | `u` | `""` | `"a"` | `(?:a(?!(())))*` | 03 |
| 15 | wrong_capture | `u` | `""` | `"a"` | `(?:a(?!((?:))))*` | 03 |
| 15 | wrong_capture | `u` | `""` | `"a"` | `(?:(?!(a))a)*` | 03 |
| 15 | wrong_span | `u` | `"a"` | `"aaaa"` | `a{1,3}?\b` | 03 |
| 15 | wrong_capture | `u` | `"a"` | `"aaaa"` | `a{1,3}?\b` | 03 |
| 13 | wrong_capture | `u` | `"a"` | `""` | `(?!((?:)))\|a` | 00 |
| 13 | wrong_capture | `u` | `"a"` | `""` | `(?!(?<g1>(?:)))\|a` | 00 |
| 12 | wrong_capture | `u` | `"a"` | `""` | `(?!())\|a` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END boost-asan r10 results -->

<!-- BEGIN boost-asan r2h results -->
### Boost.Regex 1.92 (ASan/UBSan): r2h campaign

* 136,777,312 patterns, 1369 tables, 3,221 distinct findings; self-check 244,720 probes, 0 mismatches, 0 engine failures
* findings by kind: 2,000 wrong_capture, 1,175 wrong_span, 46 wrong_result

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 70 | wrong_span | `u` | `"a"` | `"aaaa"` | `a{1,3}?\b` | 03 |
| 46 | wrong_span | `u` | `"a"` | `"aaaa"` | `a{0,2}?a$` | 03 |
| 46 | wrong_span | `u` | `"a"` | `"aaaaa"` | `a{0,3}?a$` | 03 |
| 38 | wrong_capture | `u` | `"a"` | `"aaaa"` | `a{1,3}?\b` | 03 |
| 34 | wrong_span | `u` | `""` | `"aaaa"` | `a{0,3}?(?!a)` | 03 |
| 29 | wrong_capture | `u` | `""` | `"a"` | `(?:a(?!(())))*` | 03 |
| 28 | wrong_capture | `u` | `""` | `"a"` | `(?:(?!(a))a)*` | 03 |
| 28 | wrong_capture | `u` | `""` | `"a"` | `(?:a(?!((?:))))*` | 03 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END boost-asan r2h results -->
<!-- BEGIN boost-asan r2h triage -->
### boost-asan: r2h (2-hour) campaign triage

* New: IRX-BOOST-5. After an optional or starred group with an inline case flag whose body is a loop, the next item gets the wrong case mode: `(?i:0+)?A` fails on `"0A"` (Perl, PCRE2, Python match). 59 findings.
* Known: IRX-BOOST-4 (captures kept from a failed lookaround, e.g. `(?!(a))|` on `"a"` gives group 1 `[0,1)`), about 1,630 findings; IRX-BOOST-2 (lazy bounded loops not leftmost, e.g. `a{0,3}?a$`), about 1,530.
* 503 findings in `(?x:…)` spellings with `#` comments did not reproduce in triage's isolated process; their shapes are the same three bugs.
* No ASan/UBSan reports; self-check clean.
<!-- END boost-asan r2h triage -->
