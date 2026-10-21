# Tcl 9.1 (ASan/UBSan)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py tcl-asan`.
The [`tcl`](../tcl) target on a sanitized build: Tcl 9.1.0 built with sanitizers (`tools/build_asan_big.sh tcl`), so Henry Spencer's ARE engine runs instrumented. A memory error or undefined behavior aborts the host and is recorded as a crash. Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN tcl-asan r10 results -->
### Tcl 9.1 (ASan/UBSan): r10 campaign

* 149,152 patterns, 3 tables, 59 distinct findings
* findings by kind: 59 timeout (batch)

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END tcl-asan r10 results -->

<!-- BEGIN tcl-asan r2h results -->
### Tcl 9.1 (ASan/UBSan): r2h campaign

* 1,476,800 patterns, 16 tables, 1,904 distinct findings; self-check 1,856,592 probes, 464 mismatches, 0 engine failures
* findings by kind: 1,904 timeout (batch), 24 selfcheck_mismatch (selfcheck)

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END tcl-asan r2h results -->
<!-- BEGIN tcl-asan r2h triage -->
### tcl-asan: r2h (2-hour) campaign triage

Tcl 9.1.0 (ASan/UBSan build).

* No wrong answers and no ASan/UBSan reports. The 1,904 findings are batch timeouts (Tcl's engine on nested loops, slowed further by ASan).
* Model gap, fixed: `-nocase` also matches the titlecase form of the Latin digraphs (`regexp -nocase {^Ǆ$} ǅ` is 1); all 464 self-check mismatches.
<!-- END tcl-asan r2h triage -->
