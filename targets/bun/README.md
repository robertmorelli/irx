# JavaScriptCore (Bun)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py bun`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN bun 1m results -->
### bun: 1-minute smoke campaign

* 155,296 patterns, 3 tables, 204 distinct findings; self-check 1,628,352 probes, 0 mismatches, 0 engine failures
* findings by kind: 204 timeout (batch)

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END bun 1m results -->

<!-- BEGIN bun 10m results -->
### JavaScriptCore (Bun): 10m campaign

* 1,504,096 patterns, 17 tables, 1,612 distinct findings; self-check 1,628,352 probes, 0 mismatches, 0 engine failures
* findings by kind: 1,612 timeout (batch)

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END bun 10m results -->

<!-- BEGIN bun 10m triage -->
### bun: 10-minute campaign triage

* No wrong results; self-check clean.
* 1,612 timeouts, none reproducible: a recorded batch replays in 1.8 s against the 4 s deadline, and no single
  case takes more than 0.2 s. They come from machine load (8 jobs plus background processes), not the engine.
  A larger `batch_deadline_per512_ms` would recover the ~27% of batches lost to restarts.
<!-- END bun 10m triage -->
