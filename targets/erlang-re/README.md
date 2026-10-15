# Erlang re (OTP 29)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py erlang-re`.
Erlang/OTP's `re` module (Homebrew `erlang`), which wraps PCRE2 in OTP 28+, compiled with `unicode` and `ucp`;
the host is an escript (`hosts/erlang/host.escript`) using `re:run` with `offset` and `anchored`. It shares the
`pcre2` dialect, so it checks OTP's bundled PCRE2 and its wrapper. Bugs found here are listed in the
[bug ledger](../../README.md#bug-ledger).

<!-- BEGIN erlang-re r10 results -->
### Erlang re (OTP 29): r10 campaign

* 1,293,696 patterns, 14 tables, 2,788 distinct findings
* findings by kind: 1,138 wrong_span, 1,130 wrong_result, 512 wrong_capture, 8 timeout (batch)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 4 | wrong_result | `u` | `"a"` | `""` | `(?<=a?+)a` | 00 |
| 4 | wrong_result | `u` | `"aa"` | `""` | `\P{So}+\D` | 00 |
| 3 | wrong_span | `u` | `"a"` | `""` | `\D*\P{Pc}` | 00 |
| 3 | wrong_span | `u` | `"a"` | `""` | `(?x:\P{Pc}* \D)` | 00 |
| 3 | wrong_span | `u` | `"aaaaaa"` | `""` | `(?:(?:(?:(?:(?:)*){0,3}\|)a){2,}){3,3}` | 00 |
| 3 | wrong_span | `u` | `"aa"` | `""` | `\P{Pd}+\P{Po}` | 00 |
| 3 | wrong_span | `u` | `"aa"` | `""` | `(?x:\P{Pc}+ \D)` | 00 |
| 3 | wrong_span | `u` | `"aa"` | `""` | `\P{Pc}+\D` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END erlang-re r10 results -->

<!-- BEGIN erlang-re r2h results -->
### Erlang re (OTP 29): r2h campaign

* 19,309,728 patterns, 195 tables, 12,456 distinct findings; self-check 4,602,528 probes, 0 mismatches, 0 engine failures
* findings by kind: 6,000 wrong_span, 4,000 wrong_result, 2,000 wrong_capture, 456 timeout (batch)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 37 | wrong_result | `u` | `"a"` | `""` | `(?<=a?+)a` | 00 |
| 16 | wrong_result | `u` | `"a"` | `""` | `(?<=a{0,1}+)a` | 00 |
| 16 | wrong_result | `u` | `"aa"` | `""` | `\P{Pd}+\D` | 00 |
| 12 | wrong_result | `u` | `"aa"` | `""` | `\P{Pc}+\D` | 00 |
| 12 | wrong_span | `u` | `"aa"` | `""` | `\P{Pc}+\D` | 00 |
| 11 | wrong_result | `u` | `"a"` | `""` | `\D*\P{Po}` | 00 |
| 10 | wrong_result | `u` | `"a"` | `""` | `\D*\P{Cc}` | 00 |
| 10 | wrong_result | `u` | `"aa"` | `""` | `\P{So}+\D` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END erlang-re r2h results -->
<!-- BEGIN erlang-re r2h triage -->
### erlang-re: r2h (2-hour) campaign triage

OTP 29 (PCRE2 inside `re`).

* No new IDs. IRX-PCRE2-5 widened: in the UTF interpreter with a non-zero start offset, `\b`/`\B` inside a lookbehind misread the text before the offset (`(?<=\ba)` matches `"aa"` from offset 2; `(?<!\b.)` misses `"ab"` at 2); also in plain `pcre2test` 10.49. About 1,650 findings plus the nested-lookbehind offset shapes.
* Known: IRX-PCRE2-4 (loops over negated properties/shorthands, e.g. `\P{Pc}+\D` on `"aa"`), about 8,350; IRX-PCRE2-7 (atomic groups and possessive loops in lookbehinds, e.g. `(?<=a?+)a`), about 1,800.
* Host fix: `re:run` returns `nomatch` on a match-limit hit unless given `report_errors`, so deeply nested empty loops (`(?:(?:(?:(?:a|)*|)+)+aa){3,}` on `"aaaaaa"`; plain PCRE2 reports "match limit exceeded") were read as wrong results; the host now passes `report_errors` and such cases are skipped.
* Self-check clean.
<!-- END erlang-re r2h triage -->
