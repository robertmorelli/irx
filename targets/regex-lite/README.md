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
