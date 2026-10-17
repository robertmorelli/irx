# MinRX (ASan/UBSan)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py minrx-asan`.
The [`minrx`](../minrx) target with AddressSanitizer and UndefinedBehaviorSanitizer: gawk's support library built with sanitizers (`tools/build_asan.sh`). A memory error or undefined behavior aborts the host and is recorded as a crash, even when the answer would have been right. Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN minrx-asan r10 results -->
### MinRX (ASan/UBSan): r10 campaign

* 9,684,992 patterns, 98 tables, 0 distinct findings

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END minrx-asan r10 results -->

<!-- BEGIN minrx-asan r2h results -->
### MinRX (ASan/UBSan): r2h campaign

* 104,601,024 patterns, 1048 tables, 0 distinct findings; self-check 119,992 probes, 0 mismatches, 0 engine failures

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END minrx-asan r2h results -->
<!-- BEGIN minrx-asan r2h triage -->
### minrx-asan: r2h (2-hour) campaign triage

* Clean: no findings and no ASan/UBSan reports in about 105 million patterns; self-check clean.
<!-- END minrx-asan r2h triage -->
