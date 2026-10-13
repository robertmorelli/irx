# regex-automata 0.4 backtrack

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py ra-backtrack`.
One engine of the `regex` crate's internals driven directly (`hosts/rust/src/bin/automata_host.rs`, `IRX_RA_ENGINE=backtrack`): the bounded backtracker. The `regex` crate picks among its engines per search, so each is checked here against the same `rust` dialect on its own. Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN ra-backtrack rthom results -->
### regex-automata 0.4 backtrack: rthom campaign

* 250,688 patterns, 4 tables, 70 distinct findings
* findings by kind: 50 wrong_span, 20 wrong_capture

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 3 | wrong_span | `u` | `"ϑё"` | `"a"` | `(?:(?:\B\|[^a\x{4CF}]){2})*` | 00 |
| 3 | wrong_span | `u` | `""` | `".a "` | `(?:[^K\x{DF}]{0,}?\b)*` | 03 |
| 3 | wrong_span | `u` | `"a"` | `".a "` | `(?:[^_\x{1F600}]*?){0,}\b` | 03 |
| 3 | wrong_span | `u` | `""` | `".a "` | `(?x:(?:.*? \b)*)` | 03 |
| 2 | wrong_span | `u` | `"aa a"` | `"ӏ"` | `(?:[^\x{A}\x{4CF}]*?\b)*` | 00 |
| 2 | wrong_span | `u` | `"aa a"` | `""` | `(?x:(?:[^\-\x{4CF}]*?)* \b)` | 00 |
| 2 | wrong_span | `u` | `"aa "` | `"а"` | `(?x:(?:[^\x{430}\x{401}]*?)* (?:\b\|$))` | 00 |
| 2 | wrong_span | `u` | `"aa aa"` | `"а"` | `(?:\W\|a*?)*` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END ra-backtrack rthom results -->

<!-- BEGIN ra-backtrack rnfa results -->
### regex-automata 0.4 backtrack: rnfa campaign

* 263,488 patterns, 4 tables, 0 distinct findings

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END ra-backtrack rnfa results -->
