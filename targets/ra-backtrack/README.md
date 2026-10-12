# regex-automata 0.4 backtrack

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py ra-backtrack`.
One engine of the `regex` crate's internals driven directly (`hosts/rust/src/bin/automata_host.rs`, `IRX_RA_ENGINE=backtrack`): the bounded backtracker. The `regex` crate picks among its engines per search, so each is checked here against the same `rust` dialect on its own. Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).
