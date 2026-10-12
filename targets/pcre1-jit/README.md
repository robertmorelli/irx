# PCRE1 8.45 JIT

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py pcre1-jit`.
PCRE1 8.45 (Homebrew `pcre`, deprecated upstream but still embedded in many programs) through `hosts/c/pcre1_host.c`, UTF-8 + UCP, JIT-compiled with `pcre_study`. Dialect `pcre1`: PCRE2's model with the older UCP `\w` (no Mn, Pc). Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).
