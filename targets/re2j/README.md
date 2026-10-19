# re2j 1.8

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py re2j`.
Google's pure-Java port of RE2 (`com.google.re2j`, jar from Maven Central in `vendor/re2j`), checked against the
same `re2` dialect as the C++ library. The host is the `java.util.regex` host with re2j's `Pattern`/`Matcher`;
re2j has no `region`, so there is no sticky mode. Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN re2j r10 results -->
### re2j 1.8: r10 campaign

* 10,519,456 patterns, 107 tables, 10,000 distinct findings
* findings by kind: 4,000 wrong_span, 4,000 wrong_result, 2,000 wrong_capture

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 24 | wrong_result | `iu` | `"A"` | `"aa"` | `\p{Ll}` | 00 |
| 23 | wrong_span | `iu` | `" "` | `"aaA"` | `\P{Ll}` | 03 |
| 16 | wrong_span | `iu` | `"A"` | `"aa"` | `\p{Ll}` | 00 |
| 15 | wrong_span | `iu` | `"Ё"` | `""` | `\p{Ll}` | 00 |
| 14 | wrong_span | `iu` | `""` | `"aaA"` | `\P{Ll}\|(?:)` | 03 |
| 14 | wrong_span | `iu` | `"a"` | `"aA"` | `\p{Ll}` | 03 |
| 14 | wrong_span | `iu` | `"aa"` | `"aAa"` | `\p{Ll}a` | 03 |
| 12 | wrong_capture | `iu` | `"A"` | `"aa"` | `\p{Ll}` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END re2j r10 results -->
<!-- BEGIN re2j r2h triage -->
### re2j: r2h (2-hour) campaign triage

re2j 1.8. Run stopped early (about 1h20m) when the campaign was paused.

* No new bugs. Model gap, fixed: re2j's old case-folding tables do not pair ΐ U+0390 with U+1FD3 or ΰ U+03B0 with U+1FE3; they are now kept out of the re2j pool (most findings). The rest are IRX-RE2J-1 (`(?i)\p{Ll}` misses A–Z and similar).
<!-- END re2j r2h triage -->
