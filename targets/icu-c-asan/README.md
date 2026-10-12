# ICU4C 78 regex (ASan/UBSan)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py icu-c-asan`.
The [`icu-c`](../icu-c) target on a sanitized build: ICU4C 78.3 built from source with sanitizers (`tools/build_asan_big.sh icu`). A memory error or undefined behavior aborts the host and is recorded as a crash. Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).
