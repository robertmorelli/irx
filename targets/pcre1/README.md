# PCRE1 8.45

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py pcre1`.
PCRE1 8.45 (Homebrew `pcre`, deprecated upstream but still embedded in many programs) through `hosts/c/pcre1_host.c`, UTF-8 + UCP. Dialect `pcre1`: PCRE2's model with the older UCP `\w` (no Mn, Pc). Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).
