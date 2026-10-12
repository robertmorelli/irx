# C++ std::regex, libc++ (ASan/UBSan)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py cpp-asan`.
The [`cpp-regex`](../cpp-regex) host built with AddressSanitizer and UndefinedBehaviorSanitizer (`-fsanitize=address,undefined`), with the engine itself instrumented (`std::regex` is header templates, so the host build instruments it). A memory error or undefined behavior aborts the host and is recorded as a crash, even when the answer would have been right. Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).
