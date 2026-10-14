# Boost.Regex 1.92

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py boost-regex`.
`boost::wregex` with Perl syntax over code points (Homebrew `boost`), with explicit flags because Boost's defaults
differ from Perl's (`no_mod_m` unless `m`, `mod_s` / `no_mod_s`). Default traits in the C locale give ASCII
classes and case folding, so the pool stays ASCII (dialect `boost`). Bugs found here are listed in the
[bug ledger](../../README.md#bug-ledger).

<!-- BEGIN boost-regex r10 results -->
### Boost.Regex 1.92: r10 campaign

* 22,901,024 patterns, 231 tables, 2,273 distinct findings
* findings by kind: 2,000 wrong_capture, 271 wrong_span, 2 wrong_result

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 35 | wrong_span | `u` | `"a"` | `"aaaa"` | `a{1,3}?\b` | 03 |
| 20 | wrong_capture | `u` | `""` | `"a"` | `(?:a(?!((?:))))*` | 03 |
| 18 | wrong_capture | `u` | `""` | `"a"` | `(?:a(?!(())))*` | 03 |
| 16 | wrong_capture | `u` | `""` | `"a"` | `(?:(?!(a))a)*` | 03 |
| 15 | wrong_capture | `u` | `"a"` | `"aaaa"` | `a{1,3}?\b` | 03 |
| 14 | wrong_capture | `u` | `""` | `"a"` | `(?:a(?!()))*` | 03 |
| 14 | wrong_capture | `u` | `"a"` | `""` | `(?!(?<g1>(?:)))\|a` | 00 |
| 13 | wrong_capture | `u` | `""` | `"a"` | `(?:a(?!(?<g1>())))*` | 03 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END boost-regex r10 results -->

<!-- BEGIN boost-regex r2h results -->
### Boost.Regex 1.92: r2h campaign

* 176,101,024 patterns, 1763 tables, 3,626 distinct findings; self-check 244,720 probes, 0 mismatches, 0 engine failures
* findings by kind: 2,000 wrong_capture, 1,570 wrong_span, 56 wrong_result

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 85 | wrong_span | `u` | `"a"` | `"aaaa"` | `a{1,3}?\b` | 03 |
| 80 | wrong_span | `u` | `"a"` | `"aaaaa"` | `a{0,3}?a$` | 03 |
| 61 | wrong_span | `u` | `"a"` | `"aaaa"` | `a{0,2}?a$` | 03 |
| 42 | wrong_span | `u` | `"a"` | `"aaaaa"` | `a{0,3}?a\b` | 03 |
| 40 | wrong_span | `u` | `""` | `"aaaa"` | `a{0,3}?(?!a)` | 03 |
| 38 | wrong_capture | `u` | `"a"` | `"aaaa"` | `a{1,3}?\b` | 03 |
| 29 | wrong_capture | `u` | `""` | `"a"` | `(?:a(?!(())))*` | 03 |
| 28 | wrong_capture | `u` | `""` | `"a"` | `(?:(?!(a))a)*` | 03 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END boost-regex r2h results -->
<!-- BEGIN boost-regex r2h triage -->
### boost-regex: r2h (2-hour) campaign triage

* No new bugs beyond IRX-BOOST-5 (found the same day on `boost-asan`). Every finding is a known Boost bug: IRX-BOOST-2 (lazy bounded loops not leftmost) 1,922; IRX-BOOST-4 (captures kept from a failed lookaround) 1,632; IRX-BOOST-5 (wrong case mode after an optional inline-flag group around a loop, `(?i:0+)?A` on `"0A"`) 72.
* Self-check clean.
<!-- END boost-regex r2h triage -->
