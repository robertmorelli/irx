# Python regex module (ASan/UBSan)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py python-regex-asan`.
The [`python-regex`](../python-regex) target on CPython 3.14.8 built with `--with-address-sanitizer --with-undefined-behavior-sanitizer` (`tools/build_asan_big.sh python`, into `vendor/asan/python`), so the `regex` module, compiled against it with the same flags, runs instrumented. Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN python-regex-asan r10 results -->
### Python regex module (ASan/UBSan): r10 campaign

* 401,024 patterns, 6 tables, 658 distinct findings
* findings by kind: 318 syntax_error, 144 wrong_result, 96 wrong_span, 71 wrong_capture, 29 timeout (batch)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 12 | syntax_error | `iu` | `""` | `"aa"` | `\|\p{P}\|\P{P}` | 04 |
| 6 | syntax_error | `iu` | `""` | `"aa"` | `()\|\P{Po}\|\p{Po}` | 04 |
| 6 | syntax_error | `iu` | `"aa"` | `""` | `a(?:\p{P}\|\P{P})` | 04 |
| 6 | syntax_error | `iu` | `"a"` | `"aa"` | `(?x:a (?:(?:\p{C}\|\P{C}) # c
 a)*)` | 04 |
| 6 | syntax_error | `iu` | `"ϑ"` | `""` | `(?:\p{L}\|\P{L}\|())[\x{3B1}-\x{3C9}]` | 04 |
| 6 | syntax_error | `iu` | `""` | `"aa"` | `\P{N}\|\p{N}\|` | 04 |
| 6 | syntax_error | `iu` | `""` | `"aa"` | `()\|\P{So}\|\p{So}` | 04 |
| 6 | syntax_error | `iu` | `""` | `"a"` | `(?:(?:\P{C}\|\p{C})a)*` | 04 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END python-regex-asan r10 results -->

<!-- BEGIN python-regex-asan r2h results -->
### Python regex module (ASan/UBSan): r2h campaign

* 5,974,240 patterns, 61 tables, 2,999 distinct findings; self-check 4,588,448 probes, 0 mismatches, 0 engine failures
* findings by kind: 1,842 syntax_error, 535 timeout (batch), 253 wrong_span, 244 wrong_result, 125 wrong_capture

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 24 | syntax_error | `iu` | `"a"` | `""` | `\P{Po}\|\p{Po}` | 04 |
| 18 | syntax_error | `iu` | `"aa"` | `""` | `a(?:\P{Zs}\|\p{Zs})` | 04 |
| 18 | syntax_error | `iu` | `"aa"` | `""` | `a(?:\p{P}\|\P{P})` | 04 |
| 18 | syntax_error | `iu` | `"a"` | `""` | `(?x:\P{Cc}\|\p{Cc})` | 04 |
| 18 | syntax_error | `iu` | `"a"` | `""` | `\p{So}\|\P{So}` | 04 |
| 18 | syntax_error | `iu` | `"a"` | `""` | `\p{Zl}\|\P{Zl}` | 04 |
| 16 | syntax_error | `iu` | `"a"` | `""` | `\p{Nd}\|\P{Nd}` | 04 |
| 12 | syntax_error | `iu` | `"aaaaaaaa"` | `"a"` | `(?:(?:\p{Zl}\|\P{Zl})a)*` | 04 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END python-regex-asan r2h results -->
<!-- BEGIN python-regex-asan r2h triage -->
### python-regex-asan: r2h (2-hour) campaign triage

`regex` 2026.9.29 on CPython 3.14.8 (ASan/UBSan build).

* No ASan/UBSan reports; self-check clean.
* New: IRX-PYREGEX-2 (cased properties under `IGNORECASE` match ΐ/ΰ/ŉ/ǰ alone but not after an optional item or in an alternation), IRX-PYREGEX-3 (possessive `{1}+` is not atomic: `(?:|a){1}+` matches `"a"`), IRX-PYREGEX-4 (scoped `(?-i:…)`/`(?i:…)` lost or leaked across an alternation of negated classes), IRX-PYREGEX-5 (`[^b]|[^a]` fails on `"a"`). Together most of the 622 wrong answers.
* Known: the 1,842 syntax errors are IRX-PYREGEX-1 (`\p{X}|\P{X}` under `IGNORECASE` crashes at compile). The 535 timeouts are batch timeouts on deeply nested loops.
<!-- END python-regex-asan r2h triage -->
