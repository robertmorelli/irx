# regex-automata 0.4 pikevm

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py ra-pikevm`.
One engine of the `regex` crate's internals driven directly (`hosts/rust/src/bin/automata_host.rs`, `IRX_RA_ENGINE=pikevm`): the PikeVM (NFA simulation). The `regex` crate picks among its engines per search, so each is checked here against the same `rust` dialect on its own. Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN ra-pikevm rnfa results -->
### regex-automata 0.4 pikevm: rnfa campaign

* 249,152 patterns, 4 tables, 0 distinct findings

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END ra-pikevm rnfa results -->

<!-- BEGIN ra-pikevm rglob results -->
### regex-automata 0.4 pikevm: rglob campaign

* 72,192 patterns, 2 tables, 0 distinct findings

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END ra-pikevm rglob results -->
