# RE2 (ASan/UBSan)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py re2-asan`.
The [`re2`](../re2) target with AddressSanitizer and UndefinedBehaviorSanitizer: RE2 and abseil built from source (`tools/build_asan.sh`). A memory error or undefined behavior aborts the host and is recorded as a crash, even when the answer would have been right. Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).
