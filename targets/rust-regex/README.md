# Rust regex

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py rust-regex`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN rust-regex 1m results -->
### rust-regex: 1-minute smoke campaign

* 1,203,072 patterns, 14 tables, 0 distinct findings; self-check 281,792 probes, 216 mismatches, 0 engine failures
* findings by kind: 186 selfcheck_mismatch (selfcheck)

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END rust-regex 1m results -->

<!-- BEGIN rust-regex 30s results -->
### Rust regex: 30s campaign

* 573,216 patterns, 7 tables, 0 distinct findings; self-check 281,792 probes, 216 mismatches, 0 engine failures
* findings by kind: 186 selfcheck_mismatch (selfcheck)

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END rust-regex 30s results -->

<!-- BEGIN rust-regex 10m results -->
### Rust regex: 10m campaign

* 10,844,032 patterns, 110 tables, 0 distinct findings; self-check 339,984 probes, 0 mismatches, 0 engine failures

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END rust-regex 10m results -->

<!-- BEGIN rust-regex 10m triage -->
### rust-regex: 10-minute campaign triage

* Clean: 10.8 M cases, 0 findings, self-check 0 mismatches.
<!-- END rust-regex 10m triage -->

<!-- BEGIN rust-regex 5m results -->
### Rust regex: 5m campaign

* 2,947,104 patterns, 31 tables, 0 distinct findings; self-check 339,984 probes, 0 mismatches, 0 engine failures

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END rust-regex 5m results -->

<!-- BEGIN rust-regex long-10m results -->
### Rust regex: long-10m campaign

* 297,792 patterns, 4 tables, 0 distinct findings; self-check 339,984 probes, 0 mismatches, 0 engine failures

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END rust-regex long-10m results -->

<!-- BEGIN rust-regex rstop results -->
### Rust regex: rstop campaign

* 153,760 patterns, 3 tables, 1,184 distinct findings
* findings by kind: 775 wrong_span, 409 wrong_capture

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 64 | wrong_span | `u` | `"aa"` | `"ϑ"` | `(?:\B\|a)*` | 00 |
| 57 | wrong_span | `u` | `"aa"` | `"aaϑ"` | `(?:\B\|a)*` | 02 |
| 48 | wrong_capture | `u` | `"aa"` | `"aaϑ"` | `(?:\B\|a)*` | 02 |
| 46 | wrong_capture | `u` | `"aa"` | `"ϑ"` | `(?:\B\|a)*` | 00 |
| 28 | wrong_span | `u` | `"aa"` | `"aaϑ"` | `(?:\B\|a)+` | 02 |
| 26 | wrong_capture | `u` | `"aa"` | `"aaϑ"` | `(?:\B\|a)+` | 02 |
| 26 | wrong_span | `u` | `"aa"` | `"ϑ"` | `(?:\B\|a)+` | 00 |
| 24 | wrong_span | `u` | `"aa"` | `"ӏ"` | `(?:\B\|a)*` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END rust-regex rstop results -->

<!-- BEGIN rust-regex rthom results -->
### Rust regex: rthom campaign

* 210,240 patterns, 4 tables, 36 distinct findings
* findings by kind: 24 wrong_span, 12 wrong_capture

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 2 | wrong_span | `u` | `"ϑё"` | `"a"` | `(?:(?:\B\|[^a\x{4CF}]){2})*` | 00 |
| 1 | wrong_capture | `u` | `""` | `".a "` | `(?:.*?)*\b\|()` | 03 |
| 1 | wrong_span | `u` | `""` | `".a "` | `(?:.*?)*\b\|()` | 03 |
| 1 | wrong_span | `u` | `"aa a"` | `""` | `(?x:(?:[^\-\x{4CF}]*?)* \b)` | 00 |
| 1 | wrong_span | `u` | `"a ё"` | `""` | `(?:.*?)*[ \x{451}]` | 00 |
| 1 | wrong_capture | `u` | `"a ё"` | `""` | `(?:.*?)*[ \x{451}]` | 00 |
| 1 | wrong_capture | `u` | `"aKaa"` | `""` | `(?x:a (?:a*? [K\x{DF}]*)*)` | 00 |
| 1 | wrong_span | `u` | `"Ӏaa"` | `""` | `(?:\D*?)*a` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END rust-regex rthom results -->

<!-- BEGIN rust-regex rnfa results -->
### Rust regex: rnfa campaign

* 211,264 patterns, 4 tables, 0 distinct findings

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END rust-regex rnfa results -->

<!-- BEGIN rust-regex rwb results -->
### Rust regex: rwb campaign

* 100,512 patterns, 3 tables, 0 distinct findings

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END rust-regex rwb results -->

<!-- BEGIN rust-regex rglob results -->
### Rust regex: rglob campaign

* 44,544 patterns, 2 tables, 0 distinct findings

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END rust-regex rglob results -->
