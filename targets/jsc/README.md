# JavaScriptCore (macOS system jsc)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py jsc`.
The `jsc` shell inside macOS's JavaScriptCore framework, running `driver.js` directly (YARR, the same engine family as [`bun`](../bun) but the system build and the plain shell, without Bun's runtime). Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).
