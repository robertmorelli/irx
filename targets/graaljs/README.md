# GraalJS 25.4 (TRegex)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py graaljs`.
GraalJS community (native image) from its GitHub release, unpacked into `vendor/graaljs`. Its regexps run on TRegex, an independent engine (automaton-based with a backtracking fallback), not a port of Irregexp or YARR. Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).
