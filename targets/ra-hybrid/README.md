# regex-automata 0.4 hybrid

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py ra-hybrid`.
One engine of the `regex` crate's internals driven directly (`hosts/rust/src/bin/automata_host.rs`, `IRX_RA_ENGINE=hybrid`): the lazy DFA (hybrid). The `regex` crate picks among its engines per search, so each is checked here against the same `rust` dialect on its own. Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN ra-hybrid rset results -->
### regex-automata 0.4 hybrid: rset campaign

* 127,136 patterns, 3 tables, 0 distinct findings

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END ra-hybrid rset results -->

<!-- BEGIN ra-hybrid r10 results -->
### regex-automata 0.4 hybrid: r10 campaign

* 1,782,944 patterns, 19 tables, 0 distinct findings

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END ra-hybrid r10 results -->

<!-- BEGIN ra-hybrid r2h results -->
### regex-automata 0.4 hybrid: r2h campaign

* 147,104 patterns, 3 tables, 0 distinct findings; self-check 14,298,848 probes, 719,616 mismatches, 122 engine failures
* findings by kind: 40 selfcheck_mismatch (selfcheck)

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END ra-hybrid r2h results -->
<!-- BEGIN ra-hybrid r2h triage -->
### ra-hybrid: r2h (2-hour) campaign triage

regex-automata lazy DFA (hybrid).

* No engine findings. The 40 self-check findings are the host reporting Unicode `\b` as unsupported (the lazy DFA has no Unicode word boundary), not mismatches.
* Run cut short at 04:50: from 04:37 one lane was stuck in the model again (`classEmpty`'s full Unicode scan, repeated because the NFA was rebuilt at every reference position). Fixed in irx (the built NFA and its memo are reused while the tree is unchanged); stopped with SIGINT.
<!-- END ra-hybrid r2h triage -->
