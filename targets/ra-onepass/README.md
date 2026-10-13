# regex-automata 0.4 onepass

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py ra-onepass`.
One engine of the `regex` crate's internals driven directly (`hosts/rust/src/bin/automata_host.rs`, `IRX_RA_ENGINE=onepass`): the one-pass DFA (patterns that are not one-pass are skipped). The `regex` crate picks among its engines per search, so each is checked here against the same `rust` dialect on its own. Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN ra-onepass rset results -->
### regex-automata 0.4 onepass: rset campaign

* 143,520 patterns, 3 tables, 0 distinct findings

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END ra-onepass rset results -->
