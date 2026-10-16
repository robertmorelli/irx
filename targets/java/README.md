# java.util.regex

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py java`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN java 1m results -->
### java: 1-minute smoke campaign

* 439,936 patterns, 6 tables, 1,626 distinct findings; self-check 281,792 probes, 3,492 mismatches, 0 engine failures
* findings by kind: 925 wrong_result, 544 syntax_error, 191 selfcheck_mismatch (selfcheck), 157 timeout (batch)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 6 | syntax_error | `u` | `"a"` | `""` | `(?<=(?:(?:)\|(?:)){1,1})a` | 04 |
| 6 | syntax_error | `u` | `"a"` | `""` | `(?<=(?:(?:)?){1,1})a` | 04 |
| 6 | syntax_error | `u` | `"a"` | `""` | `a(?<=(?:(?:)\|(?:)){1,1})` | 04 |
| 4 | syntax_error | `u` | `"a"` | `""` | `a(?<=(?:(?:)\|(?:)){0,2})` | 04 |
| 4 | syntax_error | `u` | `"a"` | `""` | `a(?<=(?:(?:)?){1,1})` | 04 |
| 2 | wrong_result | `su` | `""` | `"a\r"` | `(?:.$)*` | 33 |
| 2 | wrong_result | `su` | `""` | `"a\r"` | `(?:.$)*` | 03 |
| 2 | wrong_result | `u` | `"a\r"` | `""` | `a(?<!$)[^sK]` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END java 1m results -->

<!-- BEGIN java 10m results -->
### java.util.regex: 10m campaign

* 4,499,840 patterns, 46 tables, 36,550 distinct findings; self-check 339,984 probes, 212 mismatches, 0 engine failures
* findings by kind: 30,029 syntax_error, 5,073 wrong_result, 1,448 timeout (batch), 200 selfcheck_mismatch (selfcheck)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 81 | syntax_error | `u` | `""` | `"a"` | `(?<=(?:(?:)\|(?:))*)` | 04 |
| 40 | syntax_error | `u` | `""` | `"a"` | `(?<=(?:(?:)\|(?:))+)` | 04 |
| 37 | syntax_error | `u` | `"a"` | `""` | `a(?<=(?:(?:)\|(?:))*)` | 04 |
| 35 | syntax_error | `u` | `"a"` | `""` | `(?<=(?:(?:)\|(?:))*)a` | 04 |
| 34 | syntax_error | `u` | `""` | `"a"` | `(?<=(?:(?:)?)*)` | 04 |
| 28 | syntax_error | `u` | `""` | `"a"` | `(?<=(?:(?:)\|(?:)){1,1})` | 04 |
| 22 | syntax_error | `u` | `"a"` | `""` | `a\|(?<!(?:(?:)\|(?:))*)` | 04 |
| 21 | syntax_error | `u` | `""` | `"a"` | `(?<=(?:aa)*)` | 04 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END java 10m results -->

<!-- BEGIN java 10m triage -->
### java: 10-minute campaign triage

* New: **IRX-JAVA-2** (a counted group with a zero-width iteration: `(?:a|^){2}` misses `"a"`; most of the 5,073
  wrong results) and **IRX-JAVA-3** (`(?<=a*a*)` never matches).
* The 30,029 syntax errors are a **model gap**: Java rejects lookbehinds without an "obvious maximum length"
  (`(?<=(?:aa)*)`, `(?<=(?:(?:)|(?:))*)`) but accepts `(?<=a*)`. The `java` dialect should reject unbounded
  quantifiers over groups inside lookbehind.
* Self-check mismatches: the known IRX-JAVA-1 ß/ẞ asymmetry.
* 1,448 timeouts: backtracking blowups, not investigated.
<!-- END java 10m triage -->

<!-- BEGIN java 5m results -->
### java.util.regex: 5m campaign

* 1,022,528 patterns, 12 tables, 2,371 distinct findings; self-check 339,984 probes, 212 mismatches, 0 engine failures
* findings by kind: 1,426 wrong_result, 486 wrong_span, 455 timeout (batch), 200 selfcheck_mismatch (selfcheck), 4 syntax_error

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 24 | wrong_result | `u` | `"a"` | `" "` | `(?:a\|^){2,2}` | 00 |
| 20 | wrong_result | `u` | `"a"` | `" "` | `(?:^\|a){2,2}` | 00 |
| 16 | wrong_result | `u` | `"a"` | `"-"` | `(?:a\|^){2,2}` | 00 |
| 16 | wrong_result | `u` | `"a"` | `" "` | `(?:^\|a){2,}` | 00 |
| 14 | wrong_result | `u` | `"a"` | `" "` | `(?:^\|a){2}` | 00 |
| 14 | wrong_result | `u` | `"a"` | `"-"` | `(?:^\|a){2,2}` | 00 |
| 12 | wrong_span | `u` | `"a"` | `" "` | `(?:a\|^){2,2}` | 00 |
| 10 | wrong_result | `u` | `"a"` | `" "` | `(?:a\|^){2}` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END java 5m results -->

<!-- BEGIN java 30m results -->
### java.util.regex: 30m campaign

* 21,773,216 patterns, 219 tables, 79,401 distinct findings; self-check 339,984 probes, 212 mismatches, 0 engine failures
* findings by kind: 36,341 wrong_result, 22,129 wrong_capture, 18,819 wrong_span, 1,604 timeout (batch), 508 syntax_error, 200 selfcheck_mismatch (selfcheck)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 31 | wrong_result | `u` | `"a"` | `"\n"` | `(?:^a*){2,2}` | 00 |
| 24 | wrong_span | `u` | `"aa"` | `"aß"` | `(?:a\|^){2,}` | 03 |
| 24 | wrong_capture | `u` | `""` | `"a"` | `(?!(a))` | 03 |
| 19 | wrong_result | `u` | `"a"` | `" "` | `(?:^a*){2,2}` | 00 |
| 18 | wrong_capture | `u` | `"aa"` | `"aß"` | `(?:a\|^){2,}` | 03 |
| 18 | wrong_result | `u` | `""` | `"😀"` | `(?:.(?<!\x{1F600}))*` | 03 |
| 16 | wrong_span | `u` | `"aa"` | `"aK"` | `(?:a\|^){2,}` | 03 |
| 16 | wrong_result | `u` | `"a"` | `"😀"` | `.(?<!\x{1F600})` | 03 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END java 30m results -->

<!-- BEGIN java long-10m results -->
### java.util.regex: long-10m campaign

* 177,824 patterns, 3 tables, 4,102 distinct findings; self-check 339,984 probes, 212 mismatches, 0 engine failures
* findings by kind: 4,046 exception, 32 wrong_capture, 24 selfcheck_mismatch (selfcheck), 9 timeout (batch), 8 long_result, 7 wrong_span

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 3 | exception | `mu` | `"- kß "` | `"-K0ß"` | `(?:(?:[^0\x{17F}]\|(?:)\B^^\B(?<g1>[a-z]{2}?\|.))?)*` | 08 |
| 3 | exception | `mu` | `"- kß "` | `"-K0ß"` | `(?:(?:\D\|(?:(?:)\b[^\x{E0}\x{130}]\B)?)())*` | 08 |
| 3 | exception | `mu` | `"- kß "` | `"-K0ß"` | `(?:[^0\x{17F}](?:(?:)\|\|(?![^\x{212A}\x{3C3}])))*` | 08 |
| 3 | exception | `mu` | `"- kß "` | `"-K0ß"` | `(?:(?:(?![a-z])\|^)\D)*(?:)+?` | 08 |
| 3 | exception | `mu` | `"- kß "` | `"-K0ß"` | `(?:(?:(?:(?!(?:(?:)*)+?)\d\x{A}\x{3C2}S)??\D){1})+\|[a-c]` | 08 |
| 3 | exception | `mu` | `"- kß "` | `"-K0ß"` | `(?:(?:()\|\B){0,3}[^0\x{D}])*\|$` | 08 |
| 3 | exception | `mu` | `"- kß "` | `"-K0ß"` | `(?:[^\x{212A}\x{D}](?:\S\b(?:\B)+?)*)+\|(?<![^a\x{3C3}])$` | 08 |
| 3 | exception | `mu` | `"- kß "` | `"-K0ß"` | `(?:(?:(?:(?:)(?:[^bS]\|\x{3C2})[a-c][^s\x{E9}][a-z][a-c]$\|\D)?)?){1,}` | 08 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END java long-10m results -->

<!-- BEGIN java r10 results -->
### java.util.regex: r10 campaign

* 6,133,280 patterns, 63 tables, 13,178 distinct findings
* findings by kind: 6,000 wrong_span, 4,000 wrong_result, 2,000 wrong_capture, 972 syntax_error, 206 timeout (batch)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 36 | syntax_error | `u` | `""` | `"a"` | `(?<!aa*+)` | 04 |
| 30 | syntax_error | `u` | `""` | `"a"` | `(?<!aa++)` | 04 |
| 28 | wrong_span | `u` | `"aa"` | `"aϑ"` | `(?:a\|^){2,}` | 03 |
| 24 | syntax_error | `u` | `""` | `"a"` | `(?<!a*a{1,1})` | 04 |
| 24 | wrong_capture | `u` | `"aa"` | `"aϑ"` | `(?:a\|^){2,}` | 03 |
| 23 | wrong_span | `u` | `"a"` | `"aϑ"` | `(?:a\|\b){2,}` | 03 |
| 17 | wrong_capture | `u` | `"a"` | `"aϑ"` | `(?:a\|\b){2,}` | 03 |
| 15 | wrong_span | `u` | `""` | `"aϑ"` | `(?:a\|^){2,}` | 03 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END java r10 results -->

<!-- BEGIN java r2h results -->
### java.util.regex: r2h campaign

* 32,479,872 patterns, 326 tables, 15,957 distinct findings; self-check 5,116,544 probes, 0 mismatches, 0 engine failures
* findings by kind: 6,000 wrong_span, 4,000 wrong_result, 3,957 timeout (batch), 2,000 wrong_capture

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 110 | wrong_span | `mu` | `"a"` | `""` | `(?:a\|^){2,2}` | 00 |
| 98 | wrong_result | `mu` | `"a"` | `""` | `(?:a\|^){2,2}` | 00 |
| 60 | wrong_result | `mu` | `"a"` | `""` | `(?:^\|a){2,2}` | 00 |
| 56 | wrong_span | `u` | `"a"` | `"a_"` | `(?:a\|\b){2,}` | 03 |
| 47 | wrong_span | `u` | `"aa"` | `"a_"` | `(?:a\|^){2,}` | 03 |
| 46 | wrong_span | `u` | `"aa"` | `"a"` | `(?:a\|\B){2,2}` | 00 |
| 43 | wrong_capture | `u` | `"aa"` | `"a_"` | `(?:a\|^){2,}` | 03 |
| 40 | wrong_capture | `u` | `"a"` | `"a_"` | `(?:a\|\b){2,}` | 03 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END java r2h results -->
<!-- BEGIN java r2h triage -->
### java: r2h (2-hour) campaign triage

OpenJDK 27, with the OpenJDK 27 model fixes (cased `\p{Lu}`, bounded lookbehinds, range folding through shared uppercase); self-check clean (it had 88 mismatches before).

* No new engine bugs. IRX-JAVA-2 (counted group with a zero-width branch, `(?:a|^){2}` / `(?:a|\b){2,}` on `"a"`; still open in OpenJDK 27), about 4,500 findings and most of the rest; IRX-JAVA-4 (captures in nested counted loops, `(?:(a)+){2,2}` on `"aaa"`).
* Model gap, fixed after the run: lookbehind bodies are matched forward from a start position without cutting the subject, so `(?<=a?+)a` fails on `"a"` (Perl and PCRE2 agree); Java and the Perl family now keep atomic groups and possessive quantifiers out of lookbehinds.
* 3,957 batch timeouts.
<!-- END java r2h triage -->
