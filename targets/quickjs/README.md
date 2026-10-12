# QuickJS

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py quickjs`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN quickjs results -->
## QuickJS campaign results

10-minute campaign, 8 cores, modes `shell` + `shell-repeat`, edit-distance-5 A/R pairs (`campaign.toml`).
Engine: QuickJS (Homebrew `qjs --std`), direct stdin host.

* 6,598,816 patterns over 67 tables; self-check 744,480 probes, 0 mismatches.
* **0 wrong results, 0 syntax errors, 0 crashes.** All 1,255 findings are timeouts (catastrophic backtracking, not triaged).

Counts are distinct findings; one bug produces many distinct regexes. Shapes were checked on the minimized subset triaged during the campaign, and representatives were confirmed against d8 15.5 and the relation model.
<!-- END quickjs results -->

<!-- BEGIN quickjs 1m results -->
### quickjs: 1-minute smoke campaign

* 445,056 patterns, 6 tables, 1,842 distinct findings; self-check 1,628,352 probes, 392 mismatches, 0 engine failures
* findings by kind: 1,664 syntax_error, 178 timeout (batch), 172 syntax_error (selfcheck)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 254 | syntax_error | `v` | `""` | `"a"` | `(?:)\|-` | 04 |
| 206 | syntax_error | `v` | `""` | `"a"` | `-\|(?:)` | 04 |
| 166 | syntax_error | `v` | `"a"` | `""` | `a\|-` | 04 |
| 137 | syntax_error | `v` | `"a"` | `""` | `-\|a` | 04 |
| 70 | syntax_error | `v` | `""` | `"a"` | `-*` | 04 |
| 70 | syntax_error | `v` | `"a"` | `"aa"` | `-\|a` | 04 |
| 62 | syntax_error | `v` | `"a"` | `""` | `(?:-\|(?:))a` | 04 |
| 39 | syntax_error | `v` | `"a"` | `""` | `-*a` | 04 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END quickjs 1m results -->

<!-- BEGIN quickjs 10m results -->
### QuickJS: 10m campaign

* 4,461,440 patterns, 46 tables, 15,692 distinct findings; self-check 1,628,352 probes, 392 mismatches, 0 engine failures
* findings by kind: 13,968 syntax_error, 1,724 timeout (batch), 172 syntax_error (selfcheck)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 1606 | syntax_error | `v` | `""` | `"a"` | `(?:)\|-` | 04 |
| 1606 | syntax_error | `v` | `""` | `"a"` | `-\|(?:)` | 04 |
| 1136 | syntax_error | `v` | `"a"` | `""` | `-\|a` | 04 |
| 1086 | syntax_error | `v` | `""` | `"a"` | `-*` | 04 |
| 1058 | syntax_error | `v` | `"a"` | `""` | `a\|-` | 04 |
| 387 | syntax_error | `v` | `"a"` | `""` | `(?:-\|(?:))a` | 04 |
| 321 | syntax_error | `v` | `"a"` | `""` | `(?:(?:)\|-)a` | 04 |
| 278 | syntax_error | `v` | `"a"` | `""` | `a(?:(?:)\|-)` | 04 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END quickjs 10m results -->

<!-- BEGIN quickjs 10m triage -->
### quickjs: 10-minute campaign triage

* Nothing new: every finding (14,140 syntax errors) and all 392 self-check mismatches are IRX-QJS-1. A `-` outside
  a class in `v` mode is rejected.
* No wrong results. 1,724 timeouts: backtracking blowups, not investigated.
<!-- END quickjs 10m triage -->

<!-- BEGIN quickjs 5m results -->
### QuickJS: 5m campaign

* 1,604,096 patterns, 18 tables, 18,390 distinct findings; self-check 1,628,352 probes, 392 mismatches, 0 engine failures
* findings by kind: 17,949 syntax_error, 441 timeout (batch), 172 syntax_error (selfcheck)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 846 | syntax_error | `v` | `"a"` | `""` | `a\|-` | 04 |
| 796 | syntax_error | `v` | `"a"` | `""` | `-\|a` | 04 |
| 310 | syntax_error | `v` | `""` | `"a"` | `\|-` | 04 |
| 296 | syntax_error | `v` | `""` | `"a"` | `-*` | 04 |
| 279 | syntax_error | `v` | `""` | `"a"` | `(?:)\|-` | 04 |
| 273 | syntax_error | `v` | `""` | `"a"` | `-\|` | 04 |
| 260 | syntax_error | `v` | `""` | `"a"` | `-\|()` | 04 |
| 259 | syntax_error | `v` | `""` | `"a"` | `()\|-` | 04 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END quickjs 5m results -->

<!-- BEGIN quickjs 30m results -->
### QuickJS: 30m campaign

* 18,074,752 patterns, 182 tables, 396,253 distinct findings; self-check 1,628,352 probes, 392 mismatches, 0 engine failures
* findings by kind: 394,666 syntax_error, 1,587 timeout (batch), 172 syntax_error (selfcheck)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 7334 | syntax_error | `v` | `""` | `"a"` | `-*` | 04 |
| 6084 | syntax_error | `v` | `"a"` | `""` | `-\|a` | 04 |
| 5498 | syntax_error | `v` | `"a"` | `""` | `a\|-` | 04 |
| 3053 | syntax_error | `v` | `""` | `"a"` | `\|-` | 04 |
| 3052 | syntax_error | `v` | `""` | `"a"` | `-\|()` | 04 |
| 3005 | syntax_error | `v` | `""` | `"a"` | `(?:)\|-` | 04 |
| 3005 | syntax_error | `v` | `""` | `"a"` | `-\|` | 04 |
| 2851 | syntax_error | `v` | `""` | `"a"` | `()\|-` | 04 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END quickjs 30m results -->

<!-- BEGIN quickjs long-10m results -->
### QuickJS: long-10m campaign

* 269,120 patterns, 4 tables, 3,047 distinct findings; self-check 1,628,352 probes, 392 mismatches, 0 engine failures
* findings by kind: 3,043 syntax_error, 20 syntax_error (selfcheck), 4 timeout (batch)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 15 | syntax_error | `v` | `"àKſékΣk"` | `"àKéàkΣk"` | `-\|[^ \u{E0}]` | 04 |
| 12 | syntax_error | `v` | `"àKſékΣk"` | `"àKéàkΣk"` | `(?:)\|-` | 04 |
| 9 | syntax_error | `v` | `"àKſékΣk"` | `"àKéàkΣk"` | `-\|[^\u{E0}\u{130}]` | 04 |
| 9 | syntax_error | `v` | `"àKſékΣk"` | `"àKéàkΣk"` | `-\|[^b\u{E0}]` | 04 |
| 9 | syntax_error | `v` | `"àKſékΣk"` | `"àKéàkΣk"` | `-\|[^\u{E0}\u{DF}]` | 04 |
| 8 | syntax_error | `v` | `"àKſékΣk"` | `"àKéàkΣk"` | `-\|[^S\u{E0}]` | 04 |
| 6 | syntax_error | `v` | `"àKſékΣk"` | `"àKéàkΣk"` | `(?:(?:)\|-)[^\u{E0}\u{130}]` | 04 |
| 6 | syntax_error | `v` | `"àKſékΣk"` | `"àKéàkΣk"` | `-\|[^\u{212A}\u{E0}]` | 04 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END quickjs long-10m results -->
