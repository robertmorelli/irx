# Perl 5.44 /a

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py perl-a`.
The [`perl`](../perl) driver with the `/a` charset modifier on every pattern: `\d`, `\s`, `\w` and `\b` are ASCII-only (dialect `perl-a`). Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).
