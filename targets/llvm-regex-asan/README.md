# LLVM Regex (ASan/UBSan)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py llvm-regex-asan`.
The [`llvm-regex`](../llvm-regex) target with AddressSanitizer and UndefinedBehaviorSanitizer: LLVM's regex sources compiled with sanitizers (`tools/build_asan.sh`). A memory error or undefined behavior aborts the host and is recorded as a crash, even when the answer would have been right. Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).
