# ICU4C 78 (uregex C API)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py icu-c`.
ICU's C regex API (`uregex_*`) from Homebrew `icu4c@78`, the current upstream release; the [`icu`](../icu) target
reaches the older ICU that Apple ships through `NSRegularExpression`. Same `icu` dialect, plus offset and sticky
modes, which the C API supports with ICU's own semantics. Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN icu-c r10 results -->
### ICU4C 78 (uregex C API): r10 campaign

* 1,484,224 patterns, 16 tables, 8,789 distinct findings
* findings by kind: 4,974 syntax_error, 1,674 wrong_result, 1,468 wrong_span, 673 wrong_capture

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 320 | syntax_error | `u` | `""` | `"a"` | `(?<=(?=(?:)*))` | 04 |
| 144 | syntax_error | `u` | `""` | `"a"` | `(?<=(?=()*))` | 04 |
| 127 | syntax_error | `u` | `"a"` | `""` | `(?<=(?=(?:)*))a` | 04 |
| 120 | syntax_error | `u` | `"a"` | `""` | `a(?<=(?=(?:)*))` | 04 |
| 90 | syntax_error | `u` | `""` | `"a"` | `(?<=(?=(?:)+))` | 04 |
| 84 | syntax_error | `u` | `""` | `"a"` | `(?x:(?<=(?=(?:)*)))` | 04 |
| 84 | syntax_error | `u` | `"a"` | `""` | `a(?<=(?=()*))` | 04 |
| 78 | syntax_error | `u` | `""` | `"a"` | `(?:(?<!(?=(?:)*)))*` | 04 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END icu-c r10 results -->

<!-- BEGIN icu-c r2h results -->
### ICU4C 78 (uregex C API): r2h campaign

* 14,660,544 patterns, 148 tables, 128 distinct findings; self-check 4,797,600 probes, 0 mismatches, 0 engine failures
* findings by kind: 70 wrong_span, 38 wrong_result, 20 wrong_capture

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 3 | wrong_span | `u` | `"\n0"` | `"\r\n0"` | `[^\x{E9}\x{3C3}].{0,1}(?<=(?:[\x{C0}-\x{DE}]\|\D\|$\|^){1,2}?)` | 03 |
| 3 | wrong_span | `u` | `"Faıσ"` | `"S"` | `(?:[^If]*\|\s(?s:[\x{3C2}\x{B5}]\|[^\x{3C2}\x{212B}]))(?<!(?:[A-Z]\|$\b.\|^){3})` | 03 |
| 3 | wrong_span | `msu` | `"😀😀A"` | `"k"` | `(?:(?<=(?:.\|\B){3})[^\x{3C2}\-])*` | 00 |
| 3 | wrong_span | `mu` | `"​"` | `"a"` | `(?:\B\P{Pc}(?:\P{N}^)?(?:\B(?:\w\b){2,2}\|(?<=(?:.\|[0-9]\|^){3})))?` | 00 |
| 3 | wrong_span | `imu` | `"Ёϝѐ"` | `""` | `(?:.\|[^_\x{401}])*(?<=(?:\D\|\b){3}\D\|\x{2126})` | 00 |
| 3 | wrong_span | `imu` | `""` | `"k"` | `(?x:(?<!\b ^ (?:(?:\x{212A}\|$){1,2})?))` | 03 |
| 3 | wrong_span | `imsu` | `"à"` | `""` | `.(?<=(?:[k-\x{17F}]\|\B){1,2})` | 00 |
| 2 | wrong_result | `imu` | `"😀😀ᄀ🇦"` | `"가😀ᄀ🇦"` | `(?x:(?:. (?<=(?:\p{Po}\|.\|\B){2,2}))+?)` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END icu-c r2h results -->
<!-- BEGIN icu-c r2h triage -->
### icu-c: r2h (2-hour) campaign triage

ICU4C 78.3, with the two ICU model fixes from the icu-c-asan run (forward lookbehind, bounded-loop empty iterations).

* New: IRX-ICU-7 (`(?i)[\x{FB00}]` matches `"ff"`, but `[\x{FB00}a]` does not and `[\x{DF}]` does not match `"ss"`), 8 findings.
* Known: IRX-ICU-3 (counted alternation with a zero-width branch inside a lookbehind), the other ~120. Self-check clean.
<!-- END icu-c r2h triage -->
