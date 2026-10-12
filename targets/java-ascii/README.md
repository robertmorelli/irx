# java.util.regex without UNICODE_CHARACTER_CLASS

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py java-ascii`.
The [`java`](../java) host without `UNICODE_CHARACTER_CLASS` (`UNICODE_CASE` kept): ASCII `\d`, `\s`, `\w`, and `\b` following `\w` (dialect `java-ascii`). Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).
