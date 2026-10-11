# Python re

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py python-re`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN python-re 1m results -->
### python-re: 1-minute smoke campaign

* 410,240 patterns, 6 tables, 12,563 distinct findings; self-check 281,792 probes, 328 mismatches, 0 engine failures
* findings by kind: 12,459 syntax_error, 190 selfcheck_mismatch (selfcheck), 104 timeout (batch)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 75 | syntax_error | `u` | `""` | `"a"` | `(?<g0>(?:))` | 04 |
| 64 | syntax_error | `u` | `"a"` | `""` | `(?<g0>a)` | 04 |
| 41 | syntax_error | `u` | `"a"` | `""` | `a(?<g0>(?:))` | 04 |
| 30 | syntax_error | `u` | `"a"` | `""` | `(?<g0>(?:))a` | 04 |
| 18 | syntax_error | `u` | `"a"` | `""` | `a(?<=(?:)\|a)` | 04 |
| 16 | syntax_error | `u` | `"a"` | `""` | `a(?<=a\|(?:))` | 04 |
| 14 | syntax_error | `u` | `"a"` | `""` | `(?<=(?:)\|a)a` | 04 |
| 12 | syntax_error | `u` | `""` | `"a"` | `(?<=(?:)\|a)` | 04 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END python-re 1m results -->

<!-- BEGIN python-re 10m results -->
### Python re: 10m campaign

* 1,867,072 patterns, 20 tables, 1,961 distinct findings; self-check 339,984 probes, 0 mismatches, 0 engine failures
* findings by kind: 1,961 timeout (batch)

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END python-re 10m results -->

<!-- BEGIN python-re 10m triage -->
### python-re: 10-minute campaign triage

* No wrong results; self-check clean; 1.9 M cases.
* 1,961 timeouts. Timing a recorded batch case by case found one genuine exponential case (five nested lazy loops
  over an 8-character subject) and 511 fast ones: ordinary catastrophic backtracking in a backtracking engine.
<!-- END python-re 10m triage -->

<!-- BEGIN python-re 5m results -->
### Python re: 5m campaign

* 489,088 patterns, 6 tables, 533 distinct findings; self-check 339,984 probes, 0 mismatches, 0 engine failures
* findings by kind: 533 timeout (batch)

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END python-re 5m results -->

<!-- BEGIN python-re 30m results -->
### Python re: 30m campaign

* 3,050,176 patterns, 32 tables, 2,982 distinct findings; self-check 339,984 probes, 0 mismatches, 0 engine failures
* findings by kind: 2,982 timeout (batch)

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END python-re 30m results -->
