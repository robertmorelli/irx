# PCRE1 8.45 (ASan/UBSan)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py pcre1-asan`.
The [`pcre1`](../pcre1) target with AddressSanitizer and UndefinedBehaviorSanitizer: PCRE1 built from source (`tools/build_asan.sh`). A memory error or undefined behavior aborts the host and is recorded as a crash, even when the answer would have been right. Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).
