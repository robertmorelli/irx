# Boa (boa_cli)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py boa`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN boa results -->
## Boa campaign results

10-minute campaign, 8 cores, edit-distance-5 A/R pairs, via `tools/bridge.py` with object-literal batches.

* 635,328 patterns over 8 tables; self-check: 744,480 probes, 7,112 mismatches, all IRX-BOA-2 / IRX-BOA-3.
* 5,896 wrong results: IRX-BOA-3…6 (case folding, `\b` under `iv`, nested loops with `(?:){0,1}`, `v` complements).
* 2,186 timeouts (not triaged).

Counts are distinct findings; one bug produces many distinct regexes. Shapes were checked on the minimized subset triaged during the campaign, and representatives were confirmed against d8 15.5 and the relation model.
<!-- END boa results -->

<!-- BEGIN boa 1m results -->
### boa: 1-minute smoke campaign

* 53,248 patterns, 2 tables, 208 distinct findings; self-check 1,628,352 probes, 9,252 mismatches, 0 engine failures
* findings by kind: 208 timeout (batch), 182 selfcheck_mismatch (selfcheck)

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END boa 1m results -->
