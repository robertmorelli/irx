# macOS libc regex (regcomp/regexec)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py libc-regex`.
The C library's POSIX ERE matcher (on macOS the TRE-based libc regex), in the C locale so it matches bytes,
with leftmost-longest spans. It shares the Perl-to-ERE translation of [`llvm-regex`](../llvm-regex) (a separate,
Spencer-derived implementation) and the same model (`libc` dialect). Bugs found here are listed in the
[bug ledger](../../README.md#bug-ledger).
