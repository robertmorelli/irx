# LLVM Regex (ASan/UBSan)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py llvm-regex-asan`.
The [`llvm-regex`](../llvm-regex) target with AddressSanitizer and UndefinedBehaviorSanitizer: LLVM's regex sources compiled with sanitizers (`tools/build_asan.sh`). A memory error or undefined behavior aborts the host and is recorded as a crash, even when the answer would have been right. Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN llvm-regex-asan r10 results -->
### LLVM Regex (ASan/UBSan): r10 campaign

* 1,710,752 patterns, 19 tables, 6,000 distinct findings
* findings by kind: 4,000 wrong_result, 2,000 wrong_span

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 452 | wrong_result | `mu` | `"_a"` | `""` | `(?:(?:)\|.)a` | 00 |
| 238 | wrong_result | `mu` | `"_a"` | `""` | `(?:()\|.)a` | 00 |
| 188 | wrong_span | `u` | `"_a"` | `"_aa"` | `(?:(?:)\|.)a` | 02 |
| 138 | wrong_result | `mu` | `"_a"` | `""` | `(?:(?:)\|\D)a` | 00 |
| 128 | wrong_result | `u` | `"a"` | `""` | `(?:^){2,2}a` | 00 |
| 110 | wrong_result | `u` | `"a"` | `""` | `a(?:$){2,2}` | 00 |
| 93 | wrong_span | `u` | `"_a"` | `"_aa"` | `(?:()\|.)a` | 02 |
| 62 | wrong_result | `mu` | `"_a"` | `""` | `(?:()\|\D)a` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END llvm-regex-asan r10 results -->

<!-- BEGIN llvm-regex-asan r2h results -->
### LLVM Regex (ASan/UBSan): r2h campaign

* 13,765,024 patterns, 139 tables, 6,000 distinct findings; self-check 119,992 probes, 0 mismatches, 0 engine failures
* findings by kind: 4,000 wrong_result, 2,000 wrong_span

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 452 | wrong_result | `mu` | `"_a"` | `""` | `(?:(?:)\|.)a` | 00 |
| 238 | wrong_result | `mu` | `"_a"` | `""` | `(?:()\|.)a` | 00 |
| 188 | wrong_span | `u` | `"_a"` | `"_aa"` | `(?:(?:)\|.)a` | 02 |
| 138 | wrong_result | `mu` | `"_a"` | `""` | `(?:(?:)\|\D)a` | 00 |
| 128 | wrong_result | `u` | `"a"` | `""` | `(?:^){2,2}a` | 00 |
| 110 | wrong_result | `u` | `"a"` | `""` | `a(?:$){2,2}` | 00 |
| 93 | wrong_span | `u` | `"_a"` | `"_aa"` | `(?:()\|.)a` | 02 |
| 62 | wrong_result | `mu` | `"\na"` | `""` | `(?:(?:)\|\s)a` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END llvm-regex-asan r2h results -->
<!-- BEGIN llvm-regex-asan r2h triage -->
### llvm-regex-asan: r2h (2-hour) campaign triage

LLVM 23.1.3 Spencer regex (ASan/UBSan build).

* No new bugs and no ASan/UBSan reports; self-check clean. IRX-LLVM-1 (empty alternative, e.g. `(?:(?:)|.)a` on `"_a"`), about 3,600; IRX-LLVM-2 (repeated anchors, e.g. `(?:^){2,2}a` on `"a"`, also `(?:a|^){2}`), about 2,400.
<!-- END llvm-regex-asan r2h triage -->
