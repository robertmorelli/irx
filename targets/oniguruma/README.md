# Oniguruma 6.9 (C library)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py oniguruma`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN oniguruma 1m results -->
### oniguruma: 1-minute smoke campaign

* 406,144 patterns, 6 tables, 56,936 distinct findings; self-check 281,792 probes, 208 mismatches, 0 engine failures
* findings by kind: 53,586 syntax_error, 3,328 wrong_result, 193 selfcheck_mismatch (selfcheck), 22 exception

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 139 | syntax_error | `u` | `""` | `"a"` | `(?:\b)*` | 04 |
| 137 | syntax_error | `u` | `""` | `"a"` | `(?:\B)*` | 04 |
| 136 | syntax_error | `u` | `""` | `"a"` | `(?:$)*` | 04 |
| 127 | syntax_error | `u` | `""` | `"a"` | `(?:^)*` | 04 |
| 100 | syntax_error | `u` | `"a"` | `""` | `(?:$)?a` | 04 |
| 97 | syntax_error | `u` | `"a"` | `""` | `(?:\b)?a` | 04 |
| 94 | syntax_error | `u` | `""` | `"a"` | `(?:\b)?` | 04 |
| 93 | syntax_error | `u` | `""` | `"a"` | `(?:\B){0,1}` | 04 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END oniguruma 1m results -->

<!-- BEGIN oniguruma 10m results -->
### Oniguruma 6.9 (C library): 10m campaign

* 4,104,096 patterns, 43 tables, 284,252 distinct findings; self-check 281,792 probes, 0 mismatches, 0 engine failures
* findings by kind: 273,809 syntax_error, 8,816 wrong_result, 1,426 exception, 201 timeout (batch)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 54 | syntax_error | `u` | `"a"` | `""` | `(?:\b\|a)+` | 04 |
| 47 | syntax_error | `u` | `"a"` | `""` | `(?:a\|\b)+` | 04 |
| 41 | syntax_error | `u` | `""` | `"σ"` | `(?:a\|\b)*` | 04 |
| 36 | syntax_error | `u` | `""` | `"😀"` | `(?:\b\|a)*` | 04 |
| 36 | syntax_error | `u` | `""` | `"σ"` | `(?:a\|^)*` | 04 |
| 36 | syntax_error | `u` | `""` | `"😀"` | `(?:$\|a)*` | 04 |
| 33 | syntax_error | `u` | `""` | `"😀"` | `(?:a\|^)*` | 04 |
| 31 | syntax_error | `u` | `""` | `"σ"` | `(?:^\|a)*` | 04 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END oniguruma 10m results -->

<!-- BEGIN oniguruma 10m triage -->
### oniguruma: 10-minute campaign triage

* New: **IRX-ONIG-1** (shared with Ruby's Onigmo): `\A(?:^a*){2,3}\z` misses `"a"`.
* **Model gaps** (most findings):
  * 273,809 syntax errors: Oniguruma 6.9.10 rejects a quantifier on a group in which some alternative is only an
    assertion (`(?:a|\b)+`, `(?:a|^)*`, `(?:a|(?=a))*`, `(?:a|\b)?`: "target of repeat operator is invalid"), while
    `(?:a\b)*` is fine. The dialect's `allow_empty_quant = false` only covers fully zero-width bodies.
  * Wrong results with `{n}?`: in Ruby syntax `a{n}?` means `(?:a{n})?`, not a lazy exact count
    (`a{2}?a` matches `"a"`). Printing a lazy exact count as `{n}` for the Ruby dialects fixes it.
* The 1,426 exceptions are Oniguruma's retry limit on exponential patterns such as `(?:a|a)+` over 23 characters.
* Self-check clean.
<!-- END oniguruma 10m triage -->

<!-- BEGIN oniguruma 5m results -->
### Oniguruma 6.9 (C library): 5m campaign

* 1,639,936 patterns, 18 tables, 3,021 distinct findings; self-check 281,792 probes, 0 mismatches, 0 engine failures
* findings by kind: 2,221 exception, 458 wrong_result, 200 timeout (batch), 142 wrong_span

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 7 | exception | `u` | `""` | `"aaaaaaaaaaaaaaaaaaaaaa "` | `(?:a\|a)*` | 08 |
| 4 | wrong_result | `u` | `"a"` | `"_"` | `(?:^(?:()\|a)){2,}` | 00 |
| 4 | wrong_result | `u` | `"a"` | `"aa"` | `(?:(?:a\|^)\b){2,2}` | 00 |
| 4 | wrong_result | `u` | `"a"` | `"_"` | `(?:^a?){2,3}` | 00 |
| 4 | wrong_result | `u` | `"a"` | `"_"` | `(?:^a*){2,3}` | 00 |
| 3 | exception | `u` | `"aaaaaaaa"` | `""` | `(?:(?:(?:a{0,2})+(?:))+(?:a\|a\|a)a{3,3}){2}` | 08 |
| 3 | exception | `u` | `"aaaaaaa"` | `""` | `(?:(?:(?:)\|(?:(?:a?){2,})+a)\Ba{3,3}){2,2}` | 08 |
| 3 | exception | `iu` | `"k"` | `"aaa"` | `(?:(?:(?:\|(?:a*){0,2})+){2,2}){0,}K` | 08 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END oniguruma 5m results -->

<!-- BEGIN oniguruma 30m results -->
### Oniguruma 6.9 (C library): 30m campaign

* 39,534,304 patterns, 397 tables, 24,920 distinct findings; self-check 281,792 probes, 0 mismatches, 0 engine failures
* findings by kind: 10,000 wrong_result, 5,472 wrong_span, 5,280 wrong_capture, 4,168 exception

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 8 | wrong_result | `u` | `"a"` | `""` | `(?:^(?:a\|\b)){2,2}` | 00 |
| 6 | wrong_result | `u` | `"a"` | `"A"` | `(?:^a*){2,3}` | 00 |
| 6 | wrong_result | `u` | `"a"` | `""` | `(?:(?:^\|a)\b){3,}` | 00 |
| 6 | wrong_result | `u` | `"a"` | `""` | `(?:a\|^\b){2,2}` | 00 |
| 4 | wrong_result | `u` | `"a"` | `""` | `(?:a\|\b(?:a\|^)){2,}` | 00 |
| 4 | wrong_span | `u` | `"a"` | `""` | `(?:^(?:a\|\b)){2,2}` | 00 |
| 4 | exception | `u` | `"😀"` | `"aaaaaaa"` | `(?:(?:a{0,1}\|(?:))+){2,}[\x{1F600}]` | 08 |
| 4 | wrong_result | `u` | `"a"` | `"é"` | `(?:^a*){2,3}` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END oniguruma 30m results -->

<!-- BEGIN oniguruma long-10m results -->
### Oniguruma 6.9 (C library): long-10m campaign

* 210,240 patterns, 4 tables, 29 distinct findings; self-check 281,792 probes, 0 mismatches, 0 engine failures
* findings by kind: 11 wrong_span, 11 wrong_capture, 7 long_result

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 1 | wrong_span | `u` | `"-Kké_"` | `"-ſ0é"` | `(?:^\D*){2,3}` | 02 |
| 1 | wrong_span | `u` | `"-Kké_"` | `"-ſ0é"` | `(?:^[^b\x{17F}]*){2,3}` | 02 |
| 1 | wrong_capture | `u` | `"-Kké_"` | `"-ſ0é"` | `(?:^[^b\x{17F}]*){2,3}` | 02 |
| 1 | long_result | `u` | `"-Kké_"` | `"-ſ0é"` | `(?:^\D*){2,3}` | 00 |
| 1 | wrong_span | `u` | `"ba"` | `".a_"` | `(?:^[a-c]*){3,}` | 02 |
| 1 | wrong_capture | `u` | `"-Kké_"` | `"-ſ0é"` | `(?:\B[^0.]*){2,3}` | 02 |
| 1 | wrong_capture | `u` | `"-Kké_"` | `"-ſ0é"` | `(?:\B(?:[^\x{A}\x{17F}]())*){2,}` | 03 |
| 1 | wrong_span | `u` | `"-Kké_"` | `"-ſ0é"` | `(?:^(?:a\|[^\x{17F}\x{2028}]{0,})){2,2}` | 02 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END oniguruma long-10m results -->
