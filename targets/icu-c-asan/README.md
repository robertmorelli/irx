# ICU4C 78 regex (ASan/UBSan)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py icu-c-asan`.
The [`icu-c`](../icu-c) target on a sanitized build: ICU4C 78.3 built from source with sanitizers (`tools/build_asan_big.sh icu`). A memory error or undefined behavior aborts the host and is recorded as a crash. Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN icu-c-asan r10 results -->
### ICU4C 78 regex (ASan/UBSan): r10 campaign

* 398,176 patterns, 5 tables, 601 distinct findings
* findings by kind: 540 syntax_error, 27 wrong_span, 24 wrong_result, 10 wrong_capture

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 48 | syntax_error | `u` | `""` | `"a"` | `(?<=(?=(?:)*))` | 04 |
| 18 | syntax_error | `u` | `""` | `"a"` | `(?:(?<!(?=(?:)*)))*` | 04 |
| 18 | syntax_error | `u` | `"a"` | `""` | `(?<=(?=(?:)*))a` | 04 |
| 12 | syntax_error | `u` | `"a"` | `""` | `a(?<=(?=(?:)*))` | 04 |
| 12 | syntax_error | `u` | `""` | `"a"` | `(?x:(?<=(?=(?:){0,})))` | 04 |
| 12 | syntax_error | `u` | `""` | `"a"` | `(?x:(?<=(?=(?:)*)))` | 04 |
| 12 | syntax_error | `u` | `"a"` | `""` | `a(?<=(?=()+))` | 04 |
| 6 | syntax_error | `u` | `"a"` | `""` | `(?<=(?:(?!()*))?)a` | 04 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END icu-c-asan r10 results -->

<!-- BEGIN icu-c-asan r2h results -->
### ICU4C 78 regex (ASan/UBSan): r2h campaign

* 4,184,608 patterns, 43 tables, 82 distinct findings; self-check 4,797,600 probes, 0 mismatches, 0 engine failures
* findings by kind: 46 wrong_span, 20 wrong_capture, 16 wrong_result

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 4 | wrong_result | `u` | `"a"` | `""` | `a(?<=(?:a\|^){1,2})` | 00 |
| 3 | wrong_span | `u` | `"aa"` | `""` | `a*(?<=(?:a\|\b){1,2}a)` | 00 |
| 3 | wrong_span | `u` | `""` | `"a"` | `(?<=aa?+)\|\B` | 03 |
| 3 | wrong_span | `u` | `"a"` | `""` | `a(?<=(?:a\|^){1,2})` | 00 |
| 3 | wrong_span | `iu` | `""` | `"k"` | `(?x:(?<!\b ^ (?:\x{212A}\|()){0,2}))` | 03 |
| 3 | wrong_span | `u` | `"😀a"` | `"a"` | `(?:(?<=(?:.\|\B){1,2})[^\x{3C2}\-])*` | 00 |
| 3 | wrong_span | `u` | `"aaa"` | `""` | `(?:^\|a){0,2}\Ba` | 00 |
| 2 | wrong_span | `u` | `"a"` | `""` | `(?<=aa?+)` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END icu-c-asan r2h results -->
<!-- BEGIN icu-c-asan r2h triage -->
### icu-c-asan: r2h (2-hour) campaign triage

ICU4C 78.3 (ASan/UBSan build).

* No new engine bugs and no ASan/UBSan reports; self-check clean. IRX-ICU-3 (counted alternation with a zero-width branch inside a lookbehind, e.g. `a(?<=(?:a|^){1,2})` on `"a"`).
* Model gaps, fixed during the run (the run kept the old binary): ICU matches a lookbehind body forward with the subject cut at the lookbehind, so `a(?<=aa?+)` matches `"a"` (the model read it right to left; the ICU dialect now keeps atomic groups and possessive quantifiers out of lookbehinds); and ICU, like PCRE2, counts an empty iteration in a bounded repeat (`(?:^|.){0,2}a` on `" aaa"` is `[0,2)`, Perl `[0,3)`), now modelled.
* A few `(?x:…)` findings did not reproduce in a fresh process.
<!-- END icu-c-asan r2h triage -->
