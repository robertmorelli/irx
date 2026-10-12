# ICU4C 78 (uregex C API)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py icu-c`.
ICU's C regex API (`uregex_*`) from Homebrew `icu4c@78`, the current upstream release; the [`icu`](../icu) target
reaches the older ICU that Apple ships through `NSRegularExpression`. Same `icu` dialect, plus offset and sticky
modes, which the C API supports with ICU's own semantics. Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).
