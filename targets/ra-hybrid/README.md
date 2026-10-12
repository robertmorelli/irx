# regex-automata 0.4 hybrid

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py ra-hybrid`.
One engine of the `regex` crate's internals driven directly (`hosts/rust/src/bin/automata_host.rs`, `IRX_RA_ENGINE=hybrid`): the lazy DFA (hybrid). The `regex` crate picks among its engines per search, so each is checked here against the same `rust` dialect on its own. Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).
