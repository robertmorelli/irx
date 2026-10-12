# regex-automata backtracker (ASan)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py ra-backtrack-asan`.
The [`ra-backtrack`](../ra-backtrack) target with AddressSanitizer: the crate built with nightly -Zsanitizer=address (`tools/build_asan.sh`). A memory error or undefined behavior aborts the host and is recorded as a crash, even when the answer would have been right. Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).
