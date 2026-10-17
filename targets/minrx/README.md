# MinRX (gawk 5.4)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py minrx`.
MinRX, the new POSIX regex matcher in gawk 5.4 (`minrx_regcomp`/`minrx_regnexec`, from gawk's support library): POSIX ERE, leftmost-longest, C locale (`llvm` dialect). Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN minrx r10 results -->
### MinRX (gawk 5.4): r10 campaign

* 24,201,024 patterns, 244 tables, 0 distinct findings

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END minrx r10 results -->

<!-- BEGIN minrx r2h results -->
### MinRX (gawk 5.4): r2h campaign

* 196,801,024 patterns, 1970 tables, 0 distinct findings; self-check 119,992 probes, 0 mismatches, 0 engine failures

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END minrx r2h results -->
<!-- BEGIN minrx r2h triage -->
### minrx: r2h (2-hour) campaign triage

* Clean: no findings at all in about 197 million patterns; self-check clean.
<!-- END minrx r2h triage -->
