# PCRE1 8.45 (ASan/UBSan)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py pcre1-asan`.
The [`pcre1`](../pcre1) target with AddressSanitizer and UndefinedBehaviorSanitizer: PCRE1 built from source (`tools/build_asan.sh`). A memory error or undefined behavior aborts the host and is recorded as a crash, even when the answer would have been right. Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN pcre1-asan r10 results -->
### PCRE1 8.45 (ASan/UBSan): r10 campaign

* 1,321,504 patterns, 15 tables, 9,578 distinct findings
* findings by kind: 4,000 wrong_result, 3,578 wrong_span, 2,000 wrong_capture

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 100 | wrong_result | `iu` | `"ΐ"` | `""` | `\x{1FD3}` | 00 |
| 52 | wrong_span | `iu` | `"ΐ"` | `""` | `\x{1FD3}` | 00 |
| 45 | wrong_capture | `iu` | `"ΐ"` | `""` | `\x{1FD3}` | 00 |
| 40 | wrong_result | `iu` | `"ΐaΐa"` | `""` | `(?:\x{1FD3}a){1,2}` | 00 |
| 35 | wrong_result | `iu` | `"ΐ"` | `""` | `[\x{401}\x{1FD3}]` | 00 |
| 32 | wrong_span | `iu` | `"a"` | `"ΐ"` | `[^ \x{1FD3}]` | 03 |
| 26 | wrong_result | `iu` | `"ΐ"` | `""` | `[\x{451}\x{1FD3}]` | 00 |
| 25 | wrong_span | `iu` | `"ΐaΐa"` | `""` | `(?:\x{1FD3}a){1,2}` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END pcre1-asan r10 results -->

<!-- BEGIN pcre1-asan r2h results -->
### PCRE1 8.45 (ASan/UBSan): r2h campaign

* 18,838,912 patterns, 190 tables, 12,000 distinct findings; self-check 3,118,624 probes, 880 mismatches, 0 engine failures
* findings by kind: 6,000 wrong_span, 4,000 wrong_result, 2,000 wrong_capture, 26 selfcheck_mismatch (selfcheck)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 166 | wrong_result | `iu` | `"ΐ"` | `""` | `\x{1FD3}` | 00 |
| 95 | wrong_span | `iu` | `"ΐ"` | `""` | `\x{1FD3}` | 00 |
| 84 | wrong_capture | `iu` | `"ΐ"` | `""` | `\x{1FD3}` | 00 |
| 62 | wrong_result | `iu` | `"ΐ"` | `""` | `[\x{401}\x{1FD3}]` | 00 |
| 58 | wrong_result | `iu` | `"ΐaΐa"` | `""` | `(?:\x{1FD3}a){1,2}` | 00 |
| 44 | wrong_result | `iu` | `"ΐaΐa"` | `"a"` | `(?:\x{1FD3}a){0,2}` | 00 |
| 37 | wrong_span | `iu` | `"ΐ"` | `""` | `[\x{401}\x{1FD3}]` | 00 |
| 37 | wrong_span | `iu` | `"a"` | `"ΐ"` | `[^ \x{1FD3}]` | 03 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END pcre1-asan r2h results -->
<!-- BEGIN pcre1-asan r2h triage -->
### pcre1-asan: r2h (2-hour) campaign triage

PCRE1 8.45 (ASan/UBSan build).

* No new engine bugs and no ASan/UBSan reports. IRX-PCRE2-4's shape (loops over negated properties/shorthands, `\D+\P{Cc}` on `"aa"`), about 4,000.
* Model gaps, fixed: PCRE1's older Unicode data does not fold U+0390/U+1FD3 or U+03B0/U+1FE3 and gives U+1F3FB an older category; the pcre1 dialect now keeps them out of the pool. About 8,000 findings and all 880 self-check mismatches.
<!-- END pcre1-asan r2h triage -->
