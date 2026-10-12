# Rust regex-lite 0.1

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py regex-lite`.
The `regex` crate's lightweight sibling: the same syntax and leftmost-first semantics, with only basic
Unicode support (`\d`, `\s`, `\w`, `\b` and `(?i)` are ASCII-only; no `\p{…}`), modelled by the
`rust-lite` dialect. Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).
