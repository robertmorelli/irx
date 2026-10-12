# Tcl 9.1 (ASan/UBSan)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py tcl-asan`.
The [`tcl`](../tcl) target on a sanitized build: Tcl 9.1.0 built with sanitizers (`tools/build_asan_big.sh tcl`), so Henry Spencer's ARE engine runs instrumented. A memory error or undefined behavior aborts the host and is recorded as a crash. Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).
