# nim-regex (ASan/UBSan)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py nim-regex-asan`.
The [`nim-regex`](../nim-regex) target with AddressSanitizer and UndefinedBehaviorSanitizer: the nim host compiled through C with sanitizers (`tools/build_asan.sh`). A memory error or undefined behavior aborts the host and is recorded as a crash, even when the answer would have been right. Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN nim-regex-asan r10 results -->
### nim-regex (ASan/UBSan): r10 campaign

* 101,024 patterns, 3 tables, 554 distinct findings
* findings by kind: 234 timeout (batch), 133 wrong_result, 124 wrong_span, 63 wrong_capture

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 12 | wrong_result | `u` | `"a"` | `""` | `(?x:(?=(?:)) a)` | 00 |
| 8 | wrong_result | `u` | `"a"` | `""` | `(?x:(?!(?:))\|(?:) a)` | 00 |
| 8 | wrong_result | `u` | `"a"` | `""` | `(?x:(?=()) a)` | 00 |
| 8 | wrong_span | `u` | `""` | `"a"` | `(?x:(?=(?:)) (?:))` | 02 |
| 6 | wrong_result | `u` | `"ё"` | `""` | `(?x:(?=(?:)) [^a\x{430}])` | 00 |
| 6 | wrong_result | `u` | `""` | `"a"` | `(?x:(?=(?:)) (?:))` | 00 |
| 5 | wrong_capture | `u` | `"a"` | `"aa"` | `(?x:(?=(?:)) a)` | 02 |
| 5 | wrong_span | `u` | `"a"` | `"aa"` | `(?x:(?=(?:)) a)` | 02 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END nim-regex-asan r10 results -->

<!-- BEGIN nim-regex-asan r2h results -->
### nim-regex (ASan/UBSan): r2h campaign

* 1,507,680 patterns, 17 tables, 13,053 distinct findings; self-check 3,104,544 probes, 0 mismatches, 0 engine failures
* findings by kind: 4,000 wrong_result, 3,534 timeout (batch), 3,516 wrong_span, 2,000 wrong_capture, 3 exception

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 233 | wrong_result | `u` | `"a"` | `""` | `(?x:(?=(?:)) a)` | 00 |
| 188 | wrong_span | `u` | `"a"` | `""` | `(?x:(?=(?:)) a)` | 00 |
| 114 | wrong_capture | `u` | `"a"` | `""` | `(?x:(?=(?:)) a)` | 00 |
| 100 | wrong_result | `u` | `"a"` | `""` | `(?x:(?<!a) a)` | 00 |
| 94 | wrong_result | `u` | `"a"` | `""` | `(?x:(?=()) a)` | 00 |
| 75 | wrong_span | `u` | `"a"` | `""` | `(?x:(?<!a) a)` | 00 |
| 66 | wrong_span | `u` | `"a"` | `""` | `(?x:(?=()) a)` | 00 |
| 46 | wrong_capture | `u` | `"a"` | `""` | `(?x:(?<!a) a)` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END nim-regex-asan r2h results -->
<!-- BEGIN nim-regex-asan r2h triage -->
### nim-regex-asan: r2h (2-hour) campaign triage

nim-regex 0.27.0 (ASan/UBSan build; only about 1.5 million patterns in 2 hours).

* New: IRX-NIM-3 (group start moves after a counted repeat followed by a negative lookbehind: `(.{0,5}(?<!a))` on `"aa0"` → group 1 `[2,3)`); IRX-NIM-4 (`RangeDefect` int16 overflow on `(?:(?:()(?:^)*){0,3}){3}` with `"a"`), the 3 exceptions.
* Known: IRX-NIM-2 (extended-mode lookaround followed by a space, e.g. `(?x:(?=(?:)) a)`), about 9,300. No ASan/UBSan reports; self-check clean. A few capture findings were host output glitches ("invalid"). 3,534 batch timeouts.
<!-- END nim-regex-asan r2h triage -->
