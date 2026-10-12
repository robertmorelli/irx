# RE2 (longest_match)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py re2-longest`.
The [`re2`](../re2) host with `RE2::Options::set_longest_match(true)`, which switches RE2 from leftmost-first to leftmost-longest (POSIX) matching. Spans are checked against the model's leftmost-longest match (as for LLVM, Tcl and RE#);
submatches are not checked. Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).
