# Perl 5.44 (ASan/UBSan)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py perl-asan`.
The [`perl`](../perl) target on a sanitized build: Perl 5.44.0 built with `-Accflags=-fsanitize=address,undefined` (`tools/build_asan_big.sh perl`), so `regcomp.c`/`regexec.c` run instrumented. A memory error or undefined behavior aborts the host and is recorded as a crash. Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).
