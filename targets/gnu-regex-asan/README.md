# GNU regex, gawk copy (ASan/UBSan)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py gnu-regex-asan`.
The [`gnu-regex`](../gnu-regex) target with AddressSanitizer and UndefinedBehaviorSanitizer: gawk's support library built with sanitizers (`tools/build_asan.sh`). A memory error or undefined behavior aborts the host and is recorded as a crash, even when the answer would have been right. Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN gnu-regex-asan r10 results -->
### GNU regex, gawk copy (ASan/UBSan): r10 campaign

* 1,947,616 patterns, 21 tables, 135 distinct findings
* findings by kind: 135 timeout (batch)

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END gnu-regex-asan r10 results -->

<!-- BEGIN gnu-regex-asan r2h results -->
### GNU regex, gawk copy (ASan/UBSan): r2h campaign

* 27,875,776 patterns, 280 tables, 1,061 distinct findings; self-check 45,772 probes, 0 mismatches, 0 engine failures
* findings by kind: 1,061 timeout (batch)

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END gnu-regex-asan r2h results -->
<!-- BEGIN gnu-regex-asan r2h triage -->
### gnu-regex-asan: r2h (2-hour) campaign triage

* No wrong answers and no ASan/UBSan reports in about 28 million patterns; self-check clean. The 1,061 findings are batch timeouts (the ASan build is slow on large batches under load).
<!-- END gnu-regex-asan r2h triage -->
