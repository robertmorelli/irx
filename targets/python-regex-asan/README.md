# Python regex module (ASan/UBSan)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py python-regex-asan`.
The [`python-regex`](../python-regex) target on CPython 3.14.8 built with `--with-address-sanitizer --with-undefined-behavior-sanitizer` (`tools/build_asan_big.sh python`, into `vendor/asan/python`), so the `regex` module, compiled against it with the same flags, runs instrumented. Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).
