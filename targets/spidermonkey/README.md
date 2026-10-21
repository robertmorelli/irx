# SpiderMonkey 158.0b5 (jsvu)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py spidermonkey`.
Firefox's JS shell, installed with jsvu into `vendor/jsvu-home`
(`HOME=vendor/jsvu-home vendor/node/node_modules/.bin/jsvu --os=mac64arm --engines=spidermonkey`). Its regexp
engine is a port of V8's Irregexp with SpiderMonkey's own Unicode, case-folding and string handling, run by
`driver.js` directly (`scriptArgs`, `readline`). Bugs found here are listed in the
[bug ledger](../../README.md#bug-ledger).

<!-- BEGIN spidermonkey r10 results -->
### SpiderMonkey 158.0b5 (jsvu): r10 campaign

* 2,491,136 patterns, 26 tables, 112 distinct findings
* findings by kind: 86 timeout (batch), 16 wrong_span, 6 wrong_result, 4 wrong_capture

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 4 | wrong_span | `s` | `""` | `"a"` | `(?:.+?a^)*` | 03 |
| 2 | wrong_span | `s` | `" "` | `"aA"` | `(?:a\|.+?a)^(?:[a-c]*\|\b)\|[^aS]` | 02 |
| 2 | wrong_span | `s` | `""` | `"a"` | `.*?a^\|(?:)` | 02 |
| 2 | wrong_result | `s` | `" "` | `"aa"` | `.*?a^\|.` | 00 |
| 2 | wrong_span | `s` | `"a"` | `""` | `(?:.*?a^\|[^\uDE00\u03A3])(?:)` | 00 |
| 2 | wrong_result | `s` | `"a"` | `""` | `(?:.*?a^\|[^\uDE00\u03A3])(?:)` | 00 |
| 2 | wrong_result | `s` | `" "` | `""` | `.+?a^\|[^aS]` | 00 |
| 2 | wrong_span | `s` | `" "` | `" a"` | `.*?a^\|.` | 02 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END spidermonkey r10 results -->

<!-- BEGIN spidermonkey r2h results -->
### SpiderMonkey 158.0b5 (jsvu): r2h campaign

* 8,535,328 patterns, 87 tables, 1,151 distinct findings; self-check 19,969,280 probes, 7,472 mismatches, 0 engine failures
* findings by kind: 615 timeout (batch), 449 wrong_span, 54 wrong_result, 33 wrong_capture, 20 selfcheck_mismatch (selfcheck)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 12 | wrong_span | `s` | `""` | `"a"` | `(?:.*?a^)*` | 02 |
| 9 | wrong_span | `u` | `""` | `"a😀"` | `^\|(?<!a)` | 03 |
| 9 | wrong_span | `u` | `""` | `"a😀"` | `(?<!^a)` | 03 |
| 6 | wrong_span | `s` | `""` | `"a"` | `(?:.+?a^)*` | 03 |
| 6 | wrong_span | `s` | `""` | `"a"` | `.*?a^\|(?:)` | 02 |
| 6 | wrong_result | `s` | `""` | `"a"` | `(?:.*?a^)*` | 00 |
| 6 | wrong_span | `u` | `""` | `"a😀"` | `(?<!a)\|^` | 03 |
| 5 | wrong_span | `u` | `"a"` | `"😀"` | `(?<!^)\|a` | 03 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END spidermonkey r2h results -->
<!-- BEGIN spidermonkey r2h triage -->
### spidermonkey: r2h (2-hour) campaign triage

SpiderMonkey 158.0b5 (jsvu; irregexp). About 1h20m of fuzzing (paused overnight with SIGSTOP; the run's clock ran out during the pause).

* No new IDs; SpiderMonkey added to IRX-V8-2 (`/^(?:.*?a^)*$/s.test("")` → `false`) and IRX-V8-4 (`/(?!.)|a^/u.exec("😀").index` → `1`; global matches stop inside a surrogate pair). Wrong answers: surrogate-pair positions (IRX-V8-4), about 360; lazy-dot loops before `^` (IRX-V8-1/-2), about 175. Self-check mismatches: `\q{…}` under `iv` (IRX-V8-5).
<!-- END spidermonkey r2h triage -->
