# PCRE2 10.49 without UCP

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py pcre2-ascii`.
The [`pcre2`](../pcre2) host in UTF mode without `PCRE2_UCP`: ASCII `\d`, `\s`, `\w`, `\b` (PCRE2's own character tables), Unicode case folding kept (dialect `pcre2-ascii`). Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).
