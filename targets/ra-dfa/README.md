# regex-automata 0.4 dfa

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py ra-dfa`.
One engine of the `regex` crate's internals driven directly (`hosts/rust/src/bin/automata_host.rs`, `IRX_RA_ENGINE=dfa`): the dense DFA (no captures). The `regex` crate picks among its engines per search, so each is checked here against the same `rust` dialect on its own. Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).
