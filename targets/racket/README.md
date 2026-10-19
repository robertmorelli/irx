# Racket #px

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py racket`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN racket 1m results -->
### racket: 1-minute smoke campaign

* 210,240 patterns, 4 tables, 63,512 distinct findings; self-check 281,792 probes, 13,864 mismatches, 0 engine failures
* findings by kind: 37,382 wrong_result, 26,130 syntax_error, 169 selfcheck_mismatch (selfcheck)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 19 | syntax_error | `u` | `""` | `"a"` | `(?:)*` | 04 |
| 15 | syntax_error | `u` | `""` | `"a"` | `(?:){0,1}` | 04 |
| 11 | syntax_error | `u` | `""` | `"a"` | `(?:)+` | 04 |
| 7 | wrong_result | `u` | `"Σ"` | `""` | `\w` | 00 |
| 6 | syntax_error | `u` | `""` | `"a"` | `(?:){0,}` | 04 |
| 6 | wrong_result | `u` | `"aaaaΣaaa"` | `"a"` | `(?:\wa)*` | 00 |
| 5 | syntax_error | `u` | `"a"` | `""` | `a(?:){0,1}` | 04 |
| 4 | wrong_result | `u` | `"ſ"` | `""` | `\w` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END racket 1m results -->

<!-- BEGIN racket 10m results -->
### Racket #px: 10m campaign

* 11,191,648 patterns, 113 tables, 82,940 distinct findings; self-check 339,984 probes, 1,344 mismatches, 0 engine failures
* findings by kind: 80,012 wrong_result, 2,928 syntax_error, 125 selfcheck_mismatch (selfcheck)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 166 | syntax_error | `u` | `""` | `"a"` | `(?:)(?:)` | 04 |
| 26 | wrong_result | `u` | `"a"` | `""` | `(?<=(?=a))a` | 00 |
| 24 | syntax_error | `u` | `"a"` | `""` | `(?:(?:)\|(?:)(?:))a` | 04 |
| 21 | syntax_error | `u` | `"a"` | `""` | `(?:(?:)(?:)\|(?:))a` | 04 |
| 17 | syntax_error | `u` | `"a"` | `"aa"` | `(?:(?:)\|(?:)(?:))a` | 04 |
| 17 | wrong_result | `u` | `"aaa"` | `""` | `a(?<=(?=a))aa` | 00 |
| 16 | wrong_result | `u` | `"aa"` | `""` | `(?<!(?!a))aa` | 00 |
| 16 | syntax_error | `u` | `"a"` | `""` | `a(?:(?:)(?:)\|(?:))` | 04 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END racket 10m results -->

<!-- BEGIN racket 10m triage -->
### racket: 10-minute campaign triage

* New: **IRX-RACKET-2**, a lookahead inside a lookbehind that cannot see past the lookbehind's end
  (`(?<=(?=a))a` misses `"a"`).
* Known: IRX-RACKET-1 (the 2,928 syntax errors, `(?:)(?:)` → "invalid memory reference") and RACKET-1 (negated
  classes with `ſ` miss `İ`, `é`, ...; most wrong results and the 1,344 self-check mismatches).
* No timeouts; 11.2 M cases.
<!-- END racket 10m triage -->

<!-- BEGIN racket 5m results -->
### Racket #px: 5m campaign

* 1,510,752 patterns, 17 tables, 16,085 distinct findings; self-check 339,984 probes, 1,344 mismatches, 0 engine failures
* findings by kind: 9,246 wrong_result, 6,205 wrong_span, 384 timeout (batch), 250 syntax_error, 125 selfcheck_mismatch (selfcheck)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 54 | wrong_result | `u` | `"ß"` | `"aa"` | `[^ \x{17F}]` | 00 |
| 41 | wrong_span | `u` | `""` | `"aKa"` | `\B` | 03 |
| 19 | wrong_span | `u` | `"ß"` | `"aa"` | `[^ \x{17F}]` | 00 |
| 11 | wrong_result | `u` | `"ß"` | `""` | `[^ \x{17F}]` | 00 |
| 9 | syntax_error | `u` | `""` | `"a"` | `(?:)(?:)` | 04 |
| 8 | wrong_span | `u` | `""` | `"Σ"` | `(?:.(?<!.))*` | 03 |
| 8 | wrong_span | `u` | `"é"` | `"éa"` | `[^_\x{17F}]` | 02 |
| 6 | wrong_result | `u` | `"aaßaaaaa"` | `"aaa"` | `(?:[^ \x{17F}]a)+` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END racket 5m results -->

<!-- BEGIN racket long-10m results -->
### Racket #px: long-10m campaign

* 56,320 patterns, 2 tables, 1,056 distinct findings; self-check 339,984 probes, 1,344 mismatches, 0 engine failures
* findings by kind: 347 long_result, 339 wrong_capture, 339 wrong_span, 23 timeout (batch), 20 selfcheck_mismatch (selfcheck), 8 syntax_error

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 47 | long_result | `u` | `"- kß "` | `"-K0ß"` | `[^\x{17F}\x{212A}]` | 00 |
| 34 | long_result | `u` | `"- kß "` | `"-K0ß"` | `[^0\x{17F}]*` | 00 |
| 34 | long_result | `u` | `"- kß "` | `"-K0ß"` | `[^\x{17F}\x{212A}]*` | 00 |
| 34 | long_result | `u` | `"- kß "` | `"-K0ß"` | `[^0\x{17F}]` | 00 |
| 28 | long_result | `u` | `"- kß "` | `"-K0ß"` | `[^0\x{17F}]+` | 00 |
| 25 | long_result | `u` | `"- kß "` | `"-K0ß"` | `[^\x{17F}\x{212A}]+` | 00 |
| 20 | wrong_capture | `u` | `"- kß "` | `"-K0ß"` | `\B\D*` | 03 |
| 20 | wrong_span | `u` | `"- kß "` | `"-K0ß"` | `\B\D*` | 03 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END racket long-10m results -->

<!-- BEGIN racket r10 results -->
### Racket #px: r10 campaign

* 8,601,024 patterns, 88 tables, 11,294 distinct findings
* findings by kind: 4,000 wrong_result, 3,292 syntax_error, 2,000 wrong_span, 2,000 wrong_capture, 2 timeout (batch)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 61 | syntax_error | `u` | `""` | `"a"` | `(?:)(?:)` | 04 |
| 55 | wrong_result | `u` | `"ё"` | `""` | `[^\x{410}\x{4CF}]` | 00 |
| 55 | wrong_result | `u` | `"ё"` | `""` | `[^\x{430}\x{4CF}]` | 00 |
| 54 | wrong_result | `u` | `"ё"` | `""` | `[^\x{401}\x{4CF}]` | 00 |
| 28 | wrong_result | `u` | `"ё"` | `"aa"` | `[^\x{430}\x{4CF}]` | 00 |
| 17 | wrong_result | `u` | `"ё"` | `"aa"` | `[^\x{401}\x{4CF}]` | 00 |
| 13 | wrong_span | `u` | `"ё"` | `""` | `[^\x{410}\x{4CF}]` | 00 |
| 12 | wrong_capture | `u` | `"ё"` | `""` | `[^\x{410}\x{4CF}]` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END racket r10 results -->

<!-- BEGIN racket r2h results -->
### Racket #px: r2h campaign

* 145,212,288 patterns, 1454 tables, 16,278 distinct findings; self-check 3,473,184 probes, 9,832 mismatches, 0 engine failures
* findings by kind: 8,000 syntax_error, 4,000 wrong_result, 2,000 wrong_capture, 2,000 wrong_span, 278 timeout (batch), 27 selfcheck_mismatch (selfcheck)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 710 | wrong_result | `u` | `"ё"` | `""` | `[^\x{430}\x{4CF}]` | 00 |
| 664 | wrong_result | `u` | `"ё"` | `""` | `[^\x{410}\x{4CF}]` | 00 |
| 610 | wrong_result | `u` | `"ё"` | `""` | `[^\x{401}\x{4CF}]` | 00 |
| 442 | wrong_result | `u` | `"ё"` | `"aa"` | `[^\x{430}\x{4CF}]` | 00 |
| 416 | wrong_result | `u` | `"ё"` | `"aa"` | `[^\x{401}\x{4CF}]` | 00 |
| 413 | syntax_error | `u` | `""` | `"a"` | `(?:)(?:)` | 04 |
| 358 | wrong_result | `u` | `"ё"` | `"aa"` | `[^\x{410}\x{4CF}]` | 00 |
| 203 | wrong_span | `u` | `"ё"` | `""` | `[^\x{430}\x{4CF}]` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END racket r2h results -->
<!-- BEGIN racket r2h triage -->
### racket: r2h (2-hour) campaign triage

Racket 9.3 CS (`#px`).

* No new IDs. IRX-RACKET-1 (`(?:)(?:)` crash), the 8,000 syntax errors. IRX-RACKET-3 (negated classes with non-ASCII members exclude other multibyte characters), widened to two-member classes (`[^аӏ]` rejects ё): nearly all wrong answers. Self-check mismatches on classes holding `ſ` (`[^s\x{17F}]`, `[k-\x{17F}]`): IRX-RACKET-3/-1.
* Model gap, fixed: Racket's `(?i:)` does not reach `\p{…}` (`(?i:\p{Lu})` rejects a, σ and ß); the racket dialect now uses plain property matching. About 2,000 self-check mismatches.
<!-- END racket r2h triage -->
