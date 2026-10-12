# GNU regex, gawk copy (ASan/UBSan)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py gnu-regex-asan`.
The [`gnu-regex`](../gnu-regex) target with AddressSanitizer and UndefinedBehaviorSanitizer: gawk's support library built with sanitizers (`tools/build_asan.sh`). A memory error or undefined behavior aborts the host and is recorded as a crash, even when the answer would have been right. Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).
