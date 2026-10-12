# V8 linear engine

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py v8-linear`.
V8's experimental linear-time engine (`--enable-experimental-regexp-engine`, the `l` flag). It accepts no
`i`, `u` or `v` flag and no lookarounds, so the target uses only the `""` and `s` flag sets; patterns it
rejects are skipped. Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).
