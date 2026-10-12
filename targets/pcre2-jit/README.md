# PCRE2 10.49 JIT

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py pcre2-jit`.
The same host as [`pcre2`](../pcre2), with every pattern passed through `pcre2_jit_compile`, so the JIT's
matcher is checked against the same model as the interpreter. Bugs found here are listed in the
[bug ledger](../../README.md#bug-ledger).
