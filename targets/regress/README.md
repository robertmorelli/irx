# regress (Rust ECMAScript regex crate)

The regex engine Boa uses for `RegExp` (Boa 0.22 embeds regress 0.12.0), driven directly through
`hosts/rust/src/bin/regress_host.rs` instead of through `boa_cli` and the bridge: hundreds of times
more patterns per hour, and findings belong to the crate, not to Boa's JavaScript layer.
Subjects are matched as UTF-16 (`find_from_utf16` under `u`/`v`, `find_from_ucs2` otherwise, as Boa
does); cases with lone surrogates are skipped by the host protocol.
See [`target.toml`](target.toml); run it with `tools/irx_target.py regress`.
