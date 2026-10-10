# Hermes (jsvu)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py hermes`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN hermes results -->
## Hermes campaign results

10-minute campaign, 8 cores, edit-distance-5 A/R pairs, via `tools/bridge.py`; `v` flag sets excluded
(unsupported); no self-check.

* 595,232 patterns over 7 tables.
* 1,704 wrong results: IRX-HERMES-1, e.g. `/^(?:(?:(?:\W+){1,1})*\s)$/` misses `"\u2028\n"`.
* 26 exceptions: IRX-HERMES-2 (`RangeError: Maximum regex stack depth reached` on 1–2 character inputs).
* 2,236 timeouts (not triaged).

Counts are distinct findings; one bug produces many distinct regexes. Shapes were checked on the minimized subset triaged during the campaign, and representatives were confirmed against d8 15.5 and the relation model.
<!-- END hermes results -->

<!-- BEGIN hermes 1m results -->
### hermes: 1-minute smoke campaign

* 57,344 patterns, 2 tables, 224 distinct findings
* findings by kind: 224 timeout (batch)

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END hermes 1m results -->
