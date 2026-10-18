# PCRE2 10.49 (ASan/UBSan)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py pcre2-asan`.
The [`pcre2`](../pcre2) host built with AddressSanitizer and UndefinedBehaviorSanitizer (`-fsanitize=address,undefined`), with the engine itself instrumented (PCRE2 built from source into `vendor/asan`). A memory error or undefined behavior aborts the host and is recorded as a crash, even when the answer would have been right. Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN pcre2-asan r10 results -->
### PCRE2 10.49 (ASan/UBSan): r10 campaign

* 591,648 patterns, 7 tables, 1,913 distinct findings
* findings by kind: 672 wrong_result, 510 wrong_span, 409 exception, 314 wrong_capture, 8 timeout (batch)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 4 | wrong_result | `u` | `"a"` | `""` | `(?<=a?+)a` | 00 |
| 3 | wrong_span | `u` | `"aa"` | `""` | `\P{Pd}+\P{Po}` | 00 |
| 3 | wrong_span | `u` | `"a"` | `""` | `(?x:\P{Pc}* \D)` | 00 |
| 2 | wrong_span | `u` | `"a"` | `"😀aà😀a"` | `(?x:(?:\|(?<=[^\x{20}\x{E0}]?+) \D) a)` | 03 |
| 2 | wrong_result | `u` | `"a"` | `"aa"` | `(?<=a?+)a` | 00 |
| 2 | wrong_result | `u` | `"aa"` | `""` | `\P{Pd}+\P{Po}` | 00 |
| 2 | wrong_result | `u` | `"a"` | `""` | `(?x:\P{Zs}{0,123} \P{Pc})` | 00 |
| 2 | wrong_result | `u` | `"a"` | `".a"` | `\P{Po}{0,1}\P{So}` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END pcre2-asan r10 results -->

<!-- BEGIN pcre2-asan r2h results -->
### PCRE2 10.49 (ASan/UBSan): r2h campaign

* 5,987,552 patterns, 61 tables, 15,737 distinct findings; self-check 4,602,528 probes, 0 mismatches, 0 engine failures
* findings by kind: 4,838 exception, 4,825 wrong_span, 4,000 wrong_result, 2,000 wrong_capture, 74 timeout (batch)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 3 | exception | `u` | `"aaaaaa"` | `""` | `(?:(?:a*(?:(?:)*){0,3})+aa){3,}` | 08 |
| 3 | wrong_span | `u` | `"aa"` | `""` | `\D+\P{Zl}` | 00 |
| 3 | wrong_span | `u` | `"aa"` | `""` | `\P{Pd}+\P{Po}` | 00 |
| 3 | wrong_span | `u` | `"a"` | `""` | `(?x:\P{Zl}{0,} \D)` | 00 |
| 3 | wrong_span | `u` | `"aa"` | `""` | `(?x:\P{Pc}+ \D)` | 00 |
| 3 | wrong_span | `u` | `"a"` | `""` | `(?x:\P{Pc}* \D)` | 00 |
| 2 | wrong_span | `u` | `"aa"` | `"aaa"` | `(?x:\P{Pd}? \P{Cc})` | 00 |
| 2 | exception | `u` | `""` | `"aaaaS"` | `(?x:(?:(?:() (?:(?:)* a??)*)+)+)` | 08 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END pcre2-asan r2h results -->
<!-- BEGIN pcre2-asan r2h triage -->
### pcre2-asan: r2h (2-hour) campaign triage

PCRE2 10.49 (ASan/UBSan build).

* No new engine bugs and no ASan/UBSan reports; self-check clean. IRX-PCRE2-4 (loops over negated properties/shorthands), about 3,800; lookbehind shapes of IRX-PCRE2-5/-7, about 300.
* Host fix: the 4,838 exceptions were `PCRE2_ERROR_MATCHLIMIT` on deeply nested loops; the host now reports match, depth, heap and JIT-stack limits as limits (skipped). Deployed for the remaining PCRE2 targets.
<!-- END pcre2-asan r2h triage -->
