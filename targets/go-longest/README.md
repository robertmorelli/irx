# Go regexp (Longest)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py go-longest`.
The [`go-regexp`](../go-regexp) host with `Regexp.Longest()`, Go's leftmost-longest (POSIX) mode. Spans are checked against the model's leftmost-longest match (as for LLVM, Tcl and RE#);
submatches are not checked. Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN go-longest r10 results -->
### Go regexp (Longest): r10 campaign

* 21,429,184 patterns, 216 tables, 0 distinct findings

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END go-longest r10 results -->

<!-- BEGIN go-longest r2h results -->
### Go regexp (Longest): r2h campaign

* 140,415,872 patterns, 1406 tables, 4 distinct findings; self-check 3,473,184 probes, 0 mismatches, 0 engine failures
* findings by kind: 4 timeout (batch)

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END go-longest r2h results -->
<!-- BEGIN go-longest r2h triage -->
### go-longest: r2h (2-hour) campaign triage

Go 1.27.2 (`regexp.CompilePOSIX`-style leftmost-longest via `Longest()`).

* Clean: no wrong answers in about 140 million patterns; self-check clean. 4 batch timeouts.
<!-- END go-longest r2h triage -->
