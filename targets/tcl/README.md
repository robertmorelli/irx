# Tcl ARE

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py tcl`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN tcl 1m results -->
### tcl: 1-minute smoke campaign

* 307,680 patterns, 5 tables, 48,324 distinct findings; self-check 281,792 probes, 21,630 mismatches, 0 engine failures
* findings by kind: 43,542 wrong_result, 4,782 syntax_error, 200 selfcheck_mismatch (selfcheck)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 97 | wrong_result | `u` | `"aa"` | `""` | `a\Ba` | 00 |
| 91 | wrong_result | `u` | `"a"` | `""` | `\ba` | 00 |
| 72 | wrong_result | `u` | `"a"` | `""` | `a\b` | 00 |
| 50 | wrong_result | `mu` | `""` | `"\n"` | `(?:)` | 03 |
| 45 | wrong_result | `mu` | `""` | `"\n"` | `(?:)` | 33 |
| 45 | wrong_result | `u` | `"aaaaaaaa"` | `""` | `(?:a\Ba)+` | 00 |
| 44 | wrong_result | `u` | `"a"` | `"aa"` | `\ba` | 00 |
| 44 | wrong_result | `u` | `"aaaaaaaa"` | `"a"` | `(?:a\Ba)*` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END tcl 1m results -->

<!-- BEGIN tcl 10m results -->
### Tcl ARE: 10m campaign

* 1,050,176 patterns, 12 tables, 1,101 distinct findings; self-check 339,984 probes, 0 mismatches, 0 engine failures
* findings by kind: 1,101 timeout (batch)

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END tcl 10m results -->

<!-- BEGIN tcl 10m triage -->
### tcl: 10-minute campaign triage

* No wrong results in the campaign; self-check clean (after the `\A…\Z` host fix); 1.05 M cases.
* 1,101 timeouts, none reproducible: a recorded batch replays in 1.6 s against the 4 s deadline, and no case
  takes more than 0.6 s. Load-induced; a larger `batch_deadline_per512_ms` would help.
* Cross-check found **IRX-TCL-1**: `k{1}`, `k+`, `k*` with `-nocase` miss the Kelvin sign, which the bare `k` matches.
<!-- END tcl 10m triage -->

<!-- BEGIN tcl 5m results -->
### Tcl ARE: 5m campaign

* 356,320 patterns, 5 tables, 156 distinct findings; self-check 339,984 probes, 0 mismatches, 0 engine failures
* findings by kind: 156 timeout (batch)

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END tcl 5m results -->

<!-- BEGIN tcl long-10m results -->
### Tcl ARE: long-10m campaign

* 339,424 patterns, 5 tables, 3 distinct findings; self-check 339,984 probes, 0 mismatches, 0 engine failures
* findings by kind: 3 timeout (batch)

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END tcl long-10m results -->
