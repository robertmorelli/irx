# JavaScriptCore (Bun)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py bun`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN bun 1m results -->
### bun: 1-minute smoke campaign

* 155,296 patterns, 3 tables, 204 distinct findings; self-check 1,628,352 probes, 0 mismatches, 0 engine failures
* findings by kind: 204 timeout (batch)

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END bun 1m results -->
