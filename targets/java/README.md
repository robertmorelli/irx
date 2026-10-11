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
