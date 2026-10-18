# Oniguruma 6.9.10 (ASan/UBSan)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py onig-asan`.
The [`oniguruma`](../oniguruma) host built with AddressSanitizer and UndefinedBehaviorSanitizer (`-fsanitize=address,undefined`), with the engine itself instrumented (Oniguruma built from source into `vendor/asan`). A memory error or undefined behavior aborts the host and is recorded as a crash, even when the answer would have been right. Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN onig-asan r10 results -->
### Oniguruma 6.9.10 (ASan/UBSan): r10 campaign

* 4,107,168 patterns, 43 tables, 1,957 distinct findings
* findings by kind: 618 wrong_span, 586 wrong_result, 504 exception, 249 wrong_capture

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 12 | wrong_result | `u` | `"a"` | `"ϑ"` | `(?:^a*){2,3}` | 00 |
| 6 | exception | `u` | `"aaaaaa"` | `""` | `(?:(?:(?:(?:(?:()\|(?:(?:)\|a)*)*){2,2})*a){1,2}a){3,3}` | 08 |
| 6 | exception | `u` | `"aaa aa"` | `""` | `(?:(?:(?:.*){2,})+(?:a\|(?:(?:)\|)\b)a){3,}` | 08 |
| 5 | wrong_span | `u` | `"a"` | `"aϑ"` | `(?:\ba*){2,3}` | 03 |
| 5 | wrong_span | `u` | `"a"` | `"aϑ"` | `(?:\ba*){3,}` | 03 |
| 4 | exception | `u` | `"aaaa"` | `"aaKaåa"` | `(?:a(?:(?:(?:(?:.\|()){0,2})*){2,})+a){2,2}` | 08 |
| 4 | exception | `u` | `"aΐa aϑ"` | `""` | `(?:(?:(?:(?:a\|[^\x{3C9}\x{2126}]*){0,2}){0,2})*.[^a_]){3,}` | 08 |
| 4 | wrong_capture | `u` | `"a"` | `"aϑ"` | `(?:^a*){2,3}` | 02 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END onig-asan r10 results -->

<!-- BEGIN onig-asan r2h results -->
### Oniguruma 6.9.10 (ASan/UBSan): r2h campaign

* 53,512,288 patterns, 537 tables, 16,132 distinct findings; self-check 4,752,672 probes, 0 mismatches, 0 engine failures
* findings by kind: 5,876 wrong_span, 4,256 exception, 4,000 wrong_result, 2,000 wrong_capture

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 12 | wrong_result | `u` | `"a"` | `"ϑ"` | `(?:^a*){2,3}` | 00 |
| 7 | wrong_result | `u` | `"a"` | `"𝟎"` | `(?:^a*){2,3}` | 00 |
| 6 | wrong_result | `iu` | `"Saſaàa"` | `"Sſaàa"` | `(?:[k-\x{17F}]a)*` | 03 |
| 6 | wrong_result | `iu` | `"Saſaàa"` | `"Sſaàa"` | `(?:[k-\x{17F}]a)*` | 33 |
| 6 | exception | `u` | `"aaaaaa"` | `""` | `(?:(?:(?:(?:(?:()\|(?:(?:)\|a)*)*){2,2})*a){1,2}a){3,3}` | 08 |
| 6 | exception | `u` | `"aaa aa"` | `""` | `(?:(?:(?:.*){2,})+(?:a\|(?:(?:)\|)\b)a){3,}` | 08 |
| 5 | wrong_span | `su` | `""` | `"aa"` | `$.*` | 03 |
| 5 | wrong_span | `u` | `"a"` | `"aϑ"` | `(?:\ba*){2,3}` | 03 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END onig-asan r2h results -->
<!-- BEGIN onig-asan r2h triage -->
### onig-asan: r2h (2-hour) campaign triage

Oniguruma 6.9.10 (ASan/UBSan build).

* No new engine bugs and no ASan/UBSan reports; self-check clean. IRX-ONIG-1 (`(?:^a*){2,3}` on `"a"`).
* Host fix: all 4,256 exception findings were `ONIGERR_RETRY_LIMIT_IN_MATCH_OVER` (−17) on deeply nested loops, which the host reported as an exception; it now reports Oniguruma's retry and stack limits as a limit (skipped).
* Model gap, fixed: Oniguruma applies full case folding through ranges too (`(?i)[\x{C0}-\x{FF}]` matches `"ss"` via ß; also Ruby); the model only did it for listed class members. An Oniguruma self-check with the fix is clean.
* Some `\B` span findings did not reproduce in a fresh process.
<!-- END onig-asan r2h triage -->
