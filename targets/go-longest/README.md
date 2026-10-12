# Go regexp (Longest)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py go-longest`.
The [`go-regexp`](../go-regexp) host with `Regexp.Longest()`, Go's leftmost-longest (POSIX) mode. Spans are checked against the model's leftmost-longest match (as for LLVM, Tcl and RE#);
submatches are not checked. Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).
