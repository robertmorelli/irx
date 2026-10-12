# C++ std::regex (libc++)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py cpp-regex`.
The standard library's `std::regex` (libc++, shipped with Xcode) with the ECMAScript grammar, over code points
(`std::wregex`). Only the `i` and `m` flags exist, there is no lookbehind, `\p{…}` or inline modifier, and the
pool stays ASCII (dialect `cpp`). Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).
