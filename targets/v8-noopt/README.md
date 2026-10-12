# V8 no-optimization and fallback paths

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py v8-noopt`.
The same d8 as [`v8`](../v8), on regexp paths that target never takes: `--no-regexp-optimization`,
`--no-regexp-peephole-optimization`, and the fallback to the experimental linear engine after 0
backtracks. Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).
