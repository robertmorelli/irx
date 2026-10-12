# Oniguruma 6.9.10 (ASan/UBSan)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py onig-asan`.
The [`oniguruma`](../oniguruma) host built with AddressSanitizer and UndefinedBehaviorSanitizer (`-fsanitize=address,undefined`), with the engine itself instrumented (Oniguruma built from source into `vendor/asan`). A memory error or undefined behavior aborts the host and is recorded as a crash, even when the answer would have been right. Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).
