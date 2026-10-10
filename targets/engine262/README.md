# engine262

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py engine262`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN engine262 results -->
## engine262 campaign results

10-minute campaign, 8 cores, edit-distance-5 A/R pairs, via `tools/bridge.py` (no self-check: ~0.8 s per batch).

* 704,608 patterns over 9 tables.
* 9,655 `SyntaxError`s: IRX-E262-1 (`\u{…}` rejected as a `v`-mode set operand).
* 46,039 wrong results: IRX-E262-2 (negated set-operation classes), e.g. `/^[^[^a]&&\d]$/v` misses `"ſ"`.
* 802 timeouts (not triaged).

Counts are distinct findings; one bug produces many distinct regexes. Shapes were checked on the minimized subset triaged during the campaign, and representatives were confirmed against d8 15.5 and the relation model.
<!-- END engine262 results -->

<!-- BEGIN engine262 1m results -->
### engine262: 1-minute smoke campaign

* 78,848 patterns, 2 tables, 61 distinct findings
* findings by kind: 61 timeout (batch)

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END engine262 1m results -->
