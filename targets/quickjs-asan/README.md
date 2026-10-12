# QuickJS upstream (ASan)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py quickjs-asan`.
Upstream QuickJS built with `make CONFIG_ASAN=y` (`tools/build_asan.sh quickjs`, into `vendor/quickjs-asan`), so its regex engine (libregexp) and Unicode tables run under AddressSanitizer. Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).
