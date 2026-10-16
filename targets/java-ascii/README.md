# java.util.regex without UNICODE_CHARACTER_CLASS

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py java-ascii`.
The [`java`](../java) host without `UNICODE_CHARACTER_CLASS` (`UNICODE_CASE` kept): ASCII `\d`, `\s`, `\w`, and `\b` following `\w` (dialect `java-ascii`). Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN java-ascii r10 results -->
### java.util.regex without UNICODE_CHARACTER_CLASS: r10 campaign

* 6,158,368 patterns, 63 tables, 13,259 distinct findings
* findings by kind: 6,000 wrong_span, 4,000 wrong_result, 2,000 wrong_capture, 1,042 syntax_error, 217 timeout (batch)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 48 | syntax_error | `u` | `""` | `"a"` | `(?<!aa*+)` | 04 |
| 24 | syntax_error | `u` | `""` | `"a"` | `(?x:(?<!a a*+))` | 04 |
| 17 | wrong_capture | `u` | `"aa"` | `"aϑ"` | `(?:a\|^){2,}` | 03 |
| 17 | wrong_span | `u` | `"aa"` | `"aϑ"` | `(?:a\|^){2,}` | 03 |
| 12 | syntax_error | `u` | `""` | `"a"` | `(?x:(?<!a a{0,}+))` | 04 |
| 12 | syntax_error | `u` | `""` | `"a"` | `(?x:(?<!a{0,} a{1,1}))` | 04 |
| 10 | wrong_result | `u` | `"a"` | `"ϑ"` | `(?:^a*){2,}` | 00 |
| 10 | syntax_error | `u` | `""` | `"a"` | `(?<!aa++)` | 04 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END java-ascii r10 results -->

<!-- BEGIN java-ascii r2h results -->
### java.util.regex without UNICODE_CHARACTER_CLASS: r2h campaign

* 64,387,552 patterns, 645 tables, 25,746 distinct findings; self-check 5,116,544 probes, 88 mismatches, 0 engine failures
* findings by kind: 11,101 syntax_error, 6,000 wrong_span, 4,000 wrong_result, 2,645 timeout (batch), 2,000 wrong_capture, 32 selfcheck_mismatch (selfcheck)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 858 | syntax_error | `u` | `""` | `"a"` | `(?<!aa*+)` | 04 |
| 386 | wrong_result | `iu` | `"ΐ"` | `""` | `\P{Lu}` | 00 |
| 348 | syntax_error | `u` | `""` | `"a"` | `(?<!aa++)` | 04 |
| 326 | wrong_span | `iu` | `"a"` | `"ΐ"` | `\p{Lu}` | 03 |
| 269 | syntax_error | `u` | `""` | `"a"` | `(?<=a*a{0,2})` | 04 |
| 246 | syntax_error | `u` | `"a"` | `""` | `(?<!aa*+)a` | 04 |
| 218 | syntax_error | `u` | `""` | `"a"` | `(?x:(?<!a a*+))` | 04 |
| 216 | syntax_error | `u` | `""` | `"a"` | `(?<!aa{0,}+)` | 04 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END java-ascii r2h results -->
<!-- BEGIN java-ascii r2h triage -->
### java-ascii: r2h (2-hour) campaign triage

OpenJDK 27 (the run kept the binary from before the Java model fixes).

* No new engine bugs. IRX-JAVA-2 is still open on OpenJDK 27 (`Pattern.matches("(?:a|^){2}", "a")` → `false`; reopened in the ledger), the bulk of the wrong results and spans; IRX-JAVA-4 (captures in nested counted loops, e.g. `(?:(?<g1>a){1,}){2,2}` on `"aaa"`).
* Model gaps from OpenJDK 27 behaviour, fixed during the run: case-insensitive `\p{Lu}`/`\p{Ll}` mean any cased letter (about 5,200 findings); lookbehinds such as `(?<=a*a{0,2})` and `(?<!aa*+)` are rejected as unbounded (the 11,101 syntax errors; Java lookbehinds are now kept bounded); case-insensitive ranges also match through a member's shared uppercase (`[k-\x{17F}]` matches `"i"` via ı), the 88 self-check mismatches with the `\p{Lu}` ones. A Java self-check with the fixed model is clean.
* 2,645 batch timeouts.
<!-- END java-ascii r2h triage -->
