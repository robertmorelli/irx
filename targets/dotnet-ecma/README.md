# .NET RegexOptions.ECMAScript

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py dotnet-ecma`.
The [.NET host](../dotnet-interp) with `RegexOptions.ECMAScript`: ECMAScript-style `\w`, `\d`, `\s` and `\b` on the .NET matcher, only the `i` and `m` flags (dialect `dotnet-ecma`). Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN dotnet-ecma r10 results -->
### .NET RegexOptions.ECMAScript: r10 campaign

* 470,144 patterns, 6 tables, 10,940 distinct findings
* findings by kind: 5,659 wrong_span, 2,130 wrong_result, 2,000 wrong_capture, 724 exception, 400 timeout (batch), 21 tier_mismatch, 6 protocol (batch)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 12 | wrong_span | `` | `""` | `"a"` | `(?:(?:)+?)+` | 02 |
| 12 | wrong_result | `` | `"aa"` | `""` | `(?:a(?:)+?)+` | 00 |
| 10 | wrong_span | `` | `""` | `"a"` | `(?:()+?)+` | 02 |
| 10 | wrong_span | `` | `""` | `"a"` | `(?:()+?)*` | 02 |
| 9 | wrong_result | `` | `"aa"` | `"ϑ"` | `(?:a(?:)+?)*` | 00 |
| 7 | wrong_span | `` | `""` | `"a"` | `(?:(?:)+?){1,2}` | 02 |
| 7 | exception | `` | `"a"` | `"aa"` | `a(?<=(?:)+?)` | 08 |
| 7 | wrong_span | `` | `""` | `"a"` | `(?:(?:)+?)*` | 02 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END dotnet-ecma r10 results -->

<!-- BEGIN dotnet-ecma r2h results -->
### .NET RegexOptions.ECMAScript: r2h campaign

* 72,425,600 patterns, 726 tables, 12,016 distinct findings; self-check 1,728,512 probes, 0 mismatches, 0 engine failures
* findings by kind: 6,000 wrong_span, 4,000 wrong_result, 2,000 wrong_capture, 7 syntax_error, 6 timeout (batch), 3 exception

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 129 | wrong_span | `` | `"a"` | `""` | `(a)\|(?:\1)` | 03 |
| 74 | wrong_result | `` | `"a"` | `""` | `(a)\|(?:\1)` | 33 |
| 74 | wrong_result | `` | `"a"` | `""` | `(a)\|(?:\1)` | 03 |
| 68 | wrong_span | `` | `"a"` | `""` | `(?<g1>a)\|(?:\k<g1>)` | 03 |
| 60 | wrong_span | `` | `""` | `"a"` | `(?:()\|(a))(?:\2)` | 02 |
| 60 | wrong_span | `` | `""` | `"a"` | `(?:\|(a))(?:\1)` | 02 |
| 60 | wrong_capture | `` | `"a"` | `""` | `(a)\|(?:\1)` | 03 |
| 48 | wrong_result | `` | `"a"` | `""` | `(?<g1>a)\|(?:\k<g1>)` | 33 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END dotnet-ecma r2h results -->
<!-- BEGIN dotnet-ecma r2h triage -->
### dotnet-ecma: r2h (2-hour) campaign triage

Ran on .NET 11.0.0-rc.1 (the host rolls forward to the newest runtime).

* New: IRX-DOTNET-14 (the .NET 11 interpreter throws while matching `(?!\d()?|\d)`: `OverflowException`, `IndexOutOfRangeException`), the 10 exception and syntax_error findings.
* Known: IRX-DOTNET-12 (loops over `\W`, `\D`, `\P{Nd}` before `\B`), about 1,940; IRX-DOTNET-13 (counted loop over `(loop|empty)`), about 220; IRX-DOTNET-8's family (nested counted loops), about 200.
* Model gap, fixed during the run (the run kept the old binary): under `RegexOptions.ECMAScript` a backreference to a group that has not participated matches empty, as in JavaScript (`(a)|\1` matches `""`, .NET 9 and 11). About 9,600 findings.
* Self-check clean.
<!-- END dotnet-ecma r2h triage -->
