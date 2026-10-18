# PCRE2 10.49 JIT

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py pcre2-jit`.
The same host as [`pcre2`](../pcre2), with every pattern passed through `pcre2_jit_compile`, so the JIT's
matcher is checked against the same model as the interpreter. Bugs found here are listed in the
[bug ledger](../../README.md#bug-ledger).

<!-- BEGIN pcre2-jit r10 results -->
### PCRE2 10.49 JIT: r10 campaign

* 7,993,696 patterns, 81 tables, 16,964 distinct findings
* findings by kind: 5,975 wrong_span, 4,989 exception, 4,000 wrong_result, 2,000 wrong_capture

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 6 | wrong_result | `u` | `"a"` | `""` | `(?<!a?\B)a` | 00 |
| 5 | exception | `u` | `"aaaaaa"` | `""` | `(?:(?:(?:(?:a*)+){0,3})+aa){3,}` | 08 |
| 4 | exception | `u` | `"a"` | `""` | `(?:(?:(?:(?:)?){0,3}){0,2}){3,}(?:a\|\b)` | 08 |
| 4 | exception | `u` | `"aaa"` | `"ΐaa"` | `(?:(?:(?:(?:(?:){0,1}\|\V)+\|(?:()\|)*){0,2})+a){3}` | 08 |
| 4 | exception | `iu` | `"ΩθΩ"` | `"ΩaaaaaΩa"` | `(?x:(?:[\x{391}-\x{3A9}] (?:(?:(?:\|())*\|()\|.)*)+){3,3})` | 08 |
| 4 | exception | `u` | `"aaaaaa"` | `""` | `(?x:(?:(?:(?:(?:(?:)*){0,2}){2,} a){2,}){3,3})` | 08 |
| 4 | exception | `u` | `"aaaaaa"` | `""` | `(?x:(?:(?:(?:()?){0,3} a){2,}){3})` | 08 |
| 4 | exception | `u` | `"a\n"` | `"aaaa"` | `(?:\b(?:(?:(?:a\|())*){0,3})+\H){2,2}` | 08 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END pcre2-jit r10 results -->

<!-- BEGIN pcre2-jit r2h results -->
### PCRE2 10.49 JIT: r2h campaign

* 116,776,800 patterns, 1169 tables, 12,000 distinct findings; self-check 4,602,528 probes, 0 mismatches, 0 engine failures
* findings by kind: 6,000 wrong_span, 4,000 wrong_result, 2,000 wrong_capture

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 42 | wrong_result | `u` | `"aa"` | `""` | `\P{Lu}+\D` | 00 |
| 24 | wrong_result | `u` | `"a"` | `""` | `\D*\P{Po}` | 00 |
| 24 | wrong_result | `u` | `"aa"` | `""` | `\P{Pc}+\D` | 00 |
| 22 | wrong_result | `u` | `"aa"` | `""` | `\D+\P{Zl}` | 00 |
| 22 | wrong_result | `u` | `"aa"` | `""` | `\P{Pd}+\D` | 00 |
| 20 | wrong_span | `u` | `"aa"` | `""` | `\P{Pc}+\D` | 00 |
| 20 | wrong_result | `u` | `"aa"` | `""` | `\P{Cc}+\D` | 00 |
| 16 | wrong_result | `u` | `"aa"` | `""` | `\D+\P{Pc}` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END pcre2-jit r2h results -->
<!-- BEGIN pcre2-jit r2h triage -->
### pcre2-jit: r2h (2-hour) campaign triage

PCRE2 10.49 with JIT, with the limit-mapping host fix (no exception findings).

* No new bugs; self-check clean. IRX-PCRE2-4 (auto-possessified loops), about 8,950; lookbehind shapes of IRX-PCRE2-1/-5/-7 (IRX-PCRE2-1 is JIT-only), about 3,050.
<!-- END pcre2-jit r2h triage -->
