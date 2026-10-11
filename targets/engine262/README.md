# engine262

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py engine262`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN engine262 results -->
## engine262 campaign results

10-minute campaign, 8 cores, edit-distance-5 A/R pairs, via `tools/bridge.py` (no self-check: ~0.8 s per batch).

* 704,608 patterns over 9 tables.
* 9,655 `SyntaxError`s: IRX-E262-1 (`\u{…}` rejected as a `v`-mode set operand).
* 46,039 wrong results: IRX-E262-2 (negated set-operation classes), e.g. `/^[^[^a]&&\d]$/v` misses `"ſ"`.
* 802 timeouts (not triaged).

Counts are distinct findings; one bug produces many distinct regexes. Shapes were checked on the minimized subset triaged during the campaign, and representatives were confirmed against d8 15.5 and the relation model.
<!-- END engine262 results -->

<!-- BEGIN engine262 1m results -->
### engine262: 1-minute smoke campaign

* 78,848 patterns, 2 tables, 61 distinct findings
* findings by kind: 61 timeout (batch)

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END engine262 1m results -->

<!-- BEGIN engine262 10m results -->
### engine262: 10m campaign

* 729,184 patterns, 9 tables, 110,703 distinct findings
* findings by kind: 97,356 wrong_result, 13,223 syntax_error, 124 timeout (batch)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 2 | syntax_error | `v` | `"aΣ"` | `""` | `a[^[a-c]--\u{212A}]` | 04 |
| 1 | syntax_error | `v` | `"aaΣ"` | `""` | `aa[^[a-z]--\u{17F}]` | 04 |
| 1 | syntax_error | `v` | `"a"` | `""` | `(?:[^k--\u{17F}]\|(?:))a` | 04 |
| 1 | syntax_error | `v` | `"aa"` | `""` | `a[^s--\u{212A}]` | 04 |
| 1 | wrong_result | `v` | `"K"` | `""` | `[^[^a]&&\d]` | 00 |
| 1 | syntax_error | `v` | `""` | `"aa"` | `[^[A-Z]&&\u{212A}]\|(?:)` | 04 |
| 1 | syntax_error | `v` | `"aaa"` | `""` | `[^\s--\u{17F}]aa` | 04 |
| 1 | syntax_error | `v` | `"a"` | `""` | `(?:[^s--\u{212A}]\|(?:))a` | 04 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END engine262 10m results -->

<!-- BEGIN engine262 10m triage -->
### engine262: 10-minute campaign triage

* Nothing new. Every finding uses the `v` flag: the 13,223 syntax errors are IRX-E262-1 (`\u{…}` operand in a
  class set operation) and the 97,356 wrong results are IRX-E262-2 (negated classes whose contents are set
  operations, e.g. `[^\W&&s]` misses `"é"`).
* 124 timeouts; engine262 is a spec interpreter (~1,200 cases/s).
<!-- END engine262 10m triage -->

<!-- BEGIN engine262 5m results -->
### engine262: 5m campaign

* 246,080 patterns, 4 tables, 22,900 distinct findings
* findings by kind: 15,826 syntax_error, 4,724 wrong_result, 2,281 wrong_span, 69 timeout (batch)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 1 | syntax_error | `v` | `"aſaaa"` | `""` | `[^a&&\u{17F}][^ak]aaa` | 04 |
| 1 | syntax_error | `v` | `""` | `"a"` | `[\d--\u{17F}]\|(?:)` | 04 |
| 1 | syntax_error | `v` | `"aaa"` | `""` | `[^\u{212A}&&\u{17F}]aa` | 04 |
| 1 | syntax_error | `v` | `"aaa"` | `""` | `[^s&&\u{212A}]aa` | 04 |
| 1 | syntax_error | `v` | `"aΣ"` | `""` | `a(?:\W\|[\d--\u{17F}])` | 04 |
| 1 | syntax_error | `v` | `"a"` | `"aa"` | `a\|[\u{17F}&&\u{212A}]` | 04 |
| 1 | syntax_error | `v` | `"a"` | `""` | `(?:(?:)\|[^\W--\u{17F}])a` | 04 |
| 1 | syntax_error | `v` | `"a"` | `""` | `a[^[a-z]&&\u{212A}]?` | 04 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END engine262 5m results -->
