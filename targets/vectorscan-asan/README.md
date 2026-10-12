# Vectorscan (ASan/UBSan)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py vectorscan-asan`.
The [`vectorscan`](../vectorscan) target on a sanitized build: Vectorscan built from source with sanitizers (`tools/build_asan_big.sh vectorscan`). A memory error or undefined behavior aborts the host and is recorded as a crash. Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).
