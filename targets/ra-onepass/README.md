# regex-automata 0.4 onepass

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py ra-onepass`.
One engine of the `regex` crate's internals driven directly (`hosts/rust/src/bin/automata_host.rs`, `IRX_RA_ENGINE=onepass`): the one-pass DFA (patterns that are not one-pass are skipped). The `regex` crate picks among its engines per search, so each is checked here against the same `rust` dialect on its own. Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN ra-onepass rset results -->
### regex-automata 0.4 onepass: rset campaign

* 143,520 patterns, 3 tables, 0 distinct findings

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END ra-onepass rset results -->

<!-- BEGIN ra-onepass r10 results -->
### regex-automata 0.4 onepass: r10 campaign

* 1,635,840 patterns, 18 tables, 0 distinct findings

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END ra-onepass r10 results -->

<!-- BEGIN ra-onepass r2h results -->
### regex-automata 0.4 onepass: r2h campaign

* 5,495,744 patterns, 56 tables, 0 distinct findings; self-check 14,322,400 probes, 539,712 mismatches, 76 engine failures
* findings by kind: 40 selfcheck_mismatch (selfcheck)

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END ra-onepass r2h results -->
<!-- BEGIN ra-onepass r2h triage -->
### ra-onepass: r2h (2-hour) campaign triage

regex-automata one-pass DFA.

* No findings: 5.5 million patterns, no wrong answers. The self-check "mismatches" are all the host reporting unsupported (`40`: the pattern is not one-pass, or uses a Unicode word boundary); the 76 engine failures are batch-deadline timeouts.
<!-- END ra-onepass r2h triage -->
