# Ruby 4.0 Onigmo (ASan/UBSan)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py ruby-onigmo-asan`.
The [`ruby-onigmo`](../ruby-onigmo) target on a sanitized build: Ruby 4.0.7 built with sanitizers (`tools/build_asan_big.sh ruby`), so Onigmo runs instrumented. UBSan's alignment and function-type checks are suppressed (`tools/sanitizer/ruby.supp`): Ruby and Onigmo's bytecode load unaligned words by design. A memory error or undefined behavior aborts the host and is recorded as a crash. Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).
