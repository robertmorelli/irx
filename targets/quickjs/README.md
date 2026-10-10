# QuickJS

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py quickjs`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN quickjs results -->
## QuickJS campaign results

10-minute campaign, 8 cores, modes `shell` + `shell-repeat`, edit-distance-5 A/R pairs (`campaign.toml`).
Engine: QuickJS (Homebrew `qjs --std`), direct stdin host.

* 6,598,816 patterns over 67 tables; self-check 744,480 probes, 0 mismatches.
* **0 wrong results, 0 syntax errors, 0 crashes.** All 1,255 findings are timeouts (catastrophic backtracking, not triaged).

Counts are distinct findings; one bug produces many distinct regexes. Shapes were checked on the minimized subset triaged during the campaign, and representatives were confirmed against d8 15.5 and the relation model.
<!-- END quickjs results -->

<!-- BEGIN quickjs 1m results -->
### quickjs: 1-minute smoke campaign

* 445,056 patterns, 6 tables, 1,842 distinct findings; self-check 1,628,352 probes, 392 mismatches, 0 engine failures
* findings by kind: 1,664 syntax_error, 178 timeout (batch), 172 syntax_error (selfcheck)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 254 | syntax_error | `v` | `""` | `"a"` | `(?:)\|-` | 04 |
| 206 | syntax_error | `v` | `""` | `"a"` | `-\|(?:)` | 04 |
| 166 | syntax_error | `v` | `"a"` | `""` | `a\|-` | 04 |
| 137 | syntax_error | `v` | `"a"` | `""` | `-\|a` | 04 |
| 70 | syntax_error | `v` | `""` | `"a"` | `-*` | 04 |
| 70 | syntax_error | `v` | `"a"` | `"aa"` | `-\|a` | 04 |
| 62 | syntax_error | `v` | `"a"` | `""` | `(?:-\|(?:))a` | 04 |
| 39 | syntax_error | `v` | `"a"` | `""` | `-*a` | 04 |

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END quickjs 1m results -->
