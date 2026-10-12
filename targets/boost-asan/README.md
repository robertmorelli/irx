# Boost.Regex 1.92 (ASan/UBSan)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py boost-asan`.
The [`boost-regex`](../boost-regex) host built with AddressSanitizer and UndefinedBehaviorSanitizer (`-fsanitize=address,undefined`), with the engine itself instrumented (Boost.Regex is header-only, so the host build instruments it). A memory error or undefined behavior aborts the host and is recorded as a crash, even when the answer would have been right. Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).
