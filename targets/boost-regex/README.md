# Boost.Regex 1.92

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py boost-regex`.
`boost::wregex` with Perl syntax over code points (Homebrew `boost`), with explicit flags because Boost's defaults
differ from Perl's (`no_mod_m` unless `m`, `mod_s` / `no_mod_s`). Default traits in the C locale give ASCII
classes and case folding, so the pool stays ASCII (dialect `boost`). Bugs found here are listed in the
[bug ledger](../../README.md#bug-ledger).
