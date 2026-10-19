# QuickJS upstream (ASan)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py quickjs-asan`.
Upstream QuickJS built with `make CONFIG_ASAN=y` (`tools/build_asan.sh quickjs`, into `vendor/quickjs-asan`), so its regex engine (libregexp) and Unicode tables run under AddressSanitizer. Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN quickjs-asan r10 results -->
### QuickJS upstream (ASan): r10 campaign

* 1,838,400 patterns, 20 tables, 37 distinct findings
* findings by kind: 37 timeout (batch)

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END quickjs-asan r10 results -->

<!-- BEGIN quickjs-asan r2h results -->
### QuickJS upstream (ASan): r2h campaign

* 17,733,792 patterns, 179 tables, 14,690 distinct findings; self-check 21,012,224 probes, 22,288 mismatches, 0 engine failures
* findings by kind: 13,980 syntax_error, 666 timeout (batch), 27 wrong_span, 20 syntax_error (selfcheck), 12 wrong_result, 5 wrong_capture

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 63 | syntax_error | `u` | `" a"` | `""` | `[\q{\-\- \| }]a` | 04 |
| 49 | syntax_error | `u` | `" "` | `""` | `[\q{ \-\| }]` | 04 |
| 49 | syntax_error | `u` | `" "` | `""` | `[\q{\-\- \| }]` | 04 |
| 49 | syntax_error | `u` | `" a"` | `""` | `[\q{ \-\| }]a` | 04 |
| 42 | syntax_error | `u` | `""` | `"a"` | `\|[\q{\-\-\|\-}]` | 04 |
| 42 | syntax_error | `u` | `"a"` | `""` | `[\q{\-\-a\|a}]` | 04 |
| 42 | syntax_error | `u` | `"a"` | `""` | `[\q{\-\- \| }]\|a` | 04 |
| 40 | syntax_error | `u` | `"a"` | `""` | `a\|[\q{\-\- \| }]` | 04 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END quickjs-asan r2h results -->
<!-- BEGIN quickjs-asan r2h triage -->
### quickjs-asan: r2h (2-hour) campaign triage

QuickJS upstream `ea3deb1` (2026-10-12, ASan build).

* No ASan reports.
* New: IRX-QJS-3 (a multi-character `\q{…}` string inside a lookbehind is not matched backwards: `/(?<=[\q{ab}])c/v` on `"abc"` → `null`), all 44 wrong answers.
* Known: the 14,000 syntax errors and all 22,288 self-check mismatches are IRX-QJS-2 (`\-` and other escapes inside `\q{…}` rejected). The 666 timeouts are batch timeouts on deeply nested loops.
<!-- END quickjs-asan r2h triage -->
