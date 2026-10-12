# Python re, CPython 3.14 (ASan/UBSan)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py python-re-asan`.
The [`python-re`](../python-re) target on CPython 3.14.8 built with `--with-address-sanitizer --with-undefined-behavior-sanitizer` (`tools/build_asan_big.sh python`, into `vendor/asan/python`), so sre (the C engine behind `re`) runs instrumented. Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).
