# nim-regex (ASan/UBSan)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py nim-regex-asan`.
The [`nim-regex`](../nim-regex) target with AddressSanitizer and UndefinedBehaviorSanitizer: the nim host compiled through C with sanitizers (`tools/build_asan.sh`). A memory error or undefined behavior aborts the host and is recorded as a crash, even when the answer would have been right. Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).
