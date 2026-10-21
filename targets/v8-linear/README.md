# V8 linear engine

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py v8-linear`.
V8's experimental linear-time engine (`--enable-experimental-regexp-engine`, the `l` flag). It accepts no
`i`, `u` or `v` flag and no lookarounds, so the target uses only the `""` and `s` flag sets; patterns it
rejects are skipped. Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN v8-linear r10 results -->
### V8 linear engine: r10 campaign

* 21,412,288 patterns, 216 tables, 0 distinct findings

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END v8-linear r10 results -->

<!-- BEGIN v8-linear r2h results -->
### V8 linear engine: r2h campaign

* 135,404,096 patterns, 1356 tables, 0 distinct findings; self-check 926,160 probes, 0 mismatches, 0 engine failures

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END v8-linear r2h results -->
<!-- BEGIN v8-linear r2h triage -->
### v8-linear: r2h (2-hour) campaign triage

V8 15.5 experimental linear-time engine (d8 `--enable-experimental-regexp-engine`).

* Clean: 135 million patterns, no findings, self-check clean.
<!-- END v8-linear r2h triage -->
