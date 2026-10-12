# .NET RegexOptions.ECMAScript

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py dotnet-ecma`.
The [.NET host](../dotnet-interp) with `RegexOptions.ECMAScript`: ECMAScript-style `\w`, `\d`, `\s` and `\b` on the .NET matcher, only the `i` and `m` flags (dialect `dotnet-ecma`). Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).
