# Rust regex-lite 0.1

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py regex-lite`.
The `regex` crate's lightweight sibling: the same syntax and leftmost-first semantics, with only basic
Unicode support (`\d`, `\s`, `\w`, `\b` and `(?i)` are ASCII-only; no `\p{…}`), modelled by the
`rust-lite` dialect. Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN regex-lite rnfa results -->
### Rust regex-lite 0.1: rnfa campaign

* 1,897,792 patterns, 20 tables, 0 distinct findings

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END regex-lite rnfa results -->

<!-- BEGIN regex-lite rwb results -->
### Rust regex-lite 0.1: rwb campaign

* 1,700,512 patterns, 19 tables, 0 distinct findings

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END regex-lite rwb results -->

<!-- BEGIN regex-lite rset results -->
### Rust regex-lite 0.1: rset campaign

* 1,000,512 patterns, 12 tables, 0 distinct findings

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END regex-lite rset results -->

<!-- BEGIN regex-lite rglob results -->
### Rust regex-lite 0.1: rglob campaign

* 513,312 patterns, 7 tables, 0 distinct findings

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END regex-lite rglob results -->

<!-- BEGIN regex-lite r10 results -->
### Rust regex-lite 0.1: r10 campaign

* 16,477,312 patterns, 166 tables, 0 distinct findings

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END regex-lite r10 results -->

<!-- BEGIN regex-lite r2h results -->
### Rust regex-lite 0.1: r2h campaign

* 88,902,560 patterns, 891 tables, 0 distinct findings; self-check 3,971,712 probes, 304 mismatches, 0 engine failures
* findings by kind: 20 selfcheck_mismatch (selfcheck)

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END regex-lite r2h results -->
<!-- BEGIN regex-lite r2h triage -->
### regex-lite: r2h (2-hour) campaign triage

regex-lite 0.1.9.

* No findings: 89 million patterns, no wrong answers. All 304 self-check mismatches are IRX-RLITE-1 (`(?i)[[:^lower:]]` and `(?i)[[:^upper:]]` match every letter; the `regex` crate matches none).
<!-- END regex-lite r2h triage -->
