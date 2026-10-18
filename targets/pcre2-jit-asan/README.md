# PCRE2 10.49 JIT (ASan/UBSan)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py pcre2-jit-asan`.
The [`pcre2`](../pcre2) host built with AddressSanitizer and UndefinedBehaviorSanitizer (`-fsanitize=address,undefined`), with the engine itself instrumented (PCRE2 built from source into `vendor/asan`; JIT-generated code itself is not instrumented). A memory error or undefined behavior aborts the host and is recorded as a crash, even when the answer would have been right. Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN pcre2-jit-asan r10 results -->
### PCRE2 10.49 JIT (ASan/UBSan): r10 campaign

* 4,325,600 patterns, 45 tables, 15,172 distinct findings
* findings by kind: 5,071 wrong_span, 4,100 exception, 4,000 wrong_result, 2,000 wrong_capture, 1 timeout (batch)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 7 | wrong_result | `u` | `"a"` | `""` | `(?<!a?\B)a` | 00 |
| 5 | exception | `u` | `"aaaaaa"` | `""` | `(?:(?:(?:(?:a*)+){0,3})+aa){3,}` | 08 |
| 5 | wrong_result | `u` | `"a"` | `""` | `(?<=\ba?)a` | 00 |
| 4 | exception | `u` | `"aaa"` | `"ΐaa"` | `(?:(?:(?:(?:(?:){0,1}\|\V)+\|(?:()\|)*){0,2})+a){3}` | 08 |
| 4 | wrong_result | `u` | `"aa"` | `""` | `\P{N}+\P{P}` | 00 |
| 4 | exception | `u` | `"aaaaaa"` | `""` | `(?x:(?:(?:(?:(?:(?:)*){0,2}){2,} a){2,}){3,3})` | 08 |
| 4 | wrong_result | `u` | `"a"` | `""` | `\P{Cc}*\D` | 00 |
| 4 | exception | `iu` | `"µ"` | `"ǅ SıǄS"` | `(?:(?:\|(?:[^a\x{212B}]?){2,})*){0,3}\x{B5}` | 08 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END pcre2-jit-asan r10 results -->

<!-- BEGIN pcre2-jit-asan r2h results -->
### PCRE2 10.49 JIT (ASan/UBSan): r2h campaign

* 68,671,168 patterns, 688 tables, 16,967 distinct findings; self-check 4,602,528 probes, 0 mismatches, 0 engine failures
* findings by kind: 6,000 wrong_span, 4,967 exception, 4,000 wrong_result, 2,000 wrong_capture

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 42 | wrong_result | `u` | `"aa"` | `""` | `\P{Lu}+\D` | 00 |
| 24 | wrong_result | `u` | `"aa"` | `""` | `\P{Pc}+\D` | 00 |
| 24 | wrong_result | `u` | `"a"` | `""` | `\D*\P{Po}` | 00 |
| 22 | wrong_result | `u` | `"aa"` | `""` | `\D+\P{Zl}` | 00 |
| 22 | wrong_result | `u` | `"aa"` | `""` | `\P{Pd}+\D` | 00 |
| 20 | wrong_span | `u` | `"aa"` | `""` | `\P{Pc}+\D` | 00 |
| 20 | wrong_result | `u` | `"aa"` | `""` | `\P{Cc}+\D` | 00 |
| 16 | wrong_result | `u` | `"aa"` | `""` | `\D+\P{Pc}` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END pcre2-jit-asan r2h results -->
<!-- BEGIN pcre2-jit-asan r2h triage -->
### pcre2-jit-asan: r2h (2-hour) campaign triage

PCRE2 10.49 with JIT (ASan/UBSan build).

* No new engine bugs and no ASan/UBSan reports; self-check clean. IRX-PCRE2-4 (auto-possessified loops over negated properties/shorthands, also `\w+\p{Pc}a` and `\w*\x{FE0F}`), about 8,600; lookbehind shapes of IRX-PCRE2-1/-5/-7, about 3,400.
* The 4,967 exceptions are match/JIT-stack limit hits from host processes started before the limit-mapping host fix was deployed; the fixed host reports them as limits.
<!-- END pcre2-jit-asan r2h triage -->
