# V8 15.0 (Deno 2.9.7) - older V8, excluded from the ledger

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py deno`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN deno 1m results -->
### deno: 1-minute smoke campaign

* 433,792 patterns, 6 tables, 1,178 distinct findings; self-check 1,628,352 probes, 80 mismatches, 0 engine failures
* findings by kind: 1,048 wrong_result, 130 timeout (batch), 80 selfcheck_mismatch (selfcheck)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 201 | wrong_result | `mu` | `""` | `"😀"` | `(?:)` | 03 |

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END deno 1m results -->

<!-- BEGIN deno 10m results -->
### V8 15.0 (Deno 2.9.7) - older V8, excluded from the ledger: 10m campaign

* 3,826,112 patterns, 40 tables, 31,116 distinct findings; self-check 1,628,352 probes, 80 mismatches, 0 engine failures
* findings by kind: 29,827 wrong_result, 1,289 timeout (batch), 80 selfcheck_mismatch (selfcheck)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 2434 | wrong_result | `mu` | `""` | `"😀"` | `(?:)` | 03 |
| 1442 | wrong_result | `mu` | `""` | `"😀"` | `(?:)` | 33 |
| 4 | wrong_result | `mu` | `"a\raa😀a"` | `"😀"` | `(?:a\Wa)*` | 03 |
| 3 | wrong_result | `s` | `"aaaaaaaa"` | `"aaaaaaaaa"` | `(?:[^\u00DF].)*` | 33 |
| 3 | wrong_result | `s` | `"aaaaaaaa"` | `"aaaaaaaaa"` | `(?:[^\u00DF].)*` | 03 |
| 2 | wrong_result | `mu` | `"\ra.a"` | `"😀"` | `(?:\Wa)*` | 33 |
| 2 | wrong_result | `s` | `"aaaaaaaa"` | `"aaaaaaİaa"` | `(?:[^\u212A].){0,}` | 03 |
| 2 | wrong_result | `s` | `"aaaaaaaa"` | `"aaaaaaİaa"` | `(?:[^\u212A].){0,}` | 33 |

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END deno 10m results -->

<!-- BEGIN deno 10m triage -->
### deno: 10-minute campaign triage

* New (excluded from the ledger: not in d8 15.5 or Node's V8 14.1): after a warm-up match, V8 15.0's compiled
  regexp accepts odd lengths for a repeated pair of negated classes when the second excludes only non-ASCII
  (or everything, as `.` under `s` does):
  `const r = /^(?:[^a][^K])*$/; r.test("xx"); r.test("xxx")` → `true` (first call alone: `false`).
  `--regexp-interpret-all` or `--no-regexp-tier-up` fixes it, so it is in the native tier. `[^a][^b]` and
  `[^a][^\n]` are fine.
* The `mu`/`mv` findings with `😀` (`(?:)` accepting `"😀"`) and the `\B[^]*` self-check mismatches are the
  surrogate-pair family (IRX-V8-3, V8-2).
* 1,289 timeouts: load-induced, as for Bun.
<!-- END deno 10m triage -->

<!-- BEGIN deno 5m results -->
### V8 15.0 (Deno 2.9.7) - older V8, excluded from the ledger: 5m campaign

* 1,001,024 patterns, 12 tables, 10,852 distinct findings; self-check 1,628,352 probes, 80 mismatches, 0 engine failures
* findings by kind: 10,179 wrong_result, 372 timeout (batch), 301 wrong_span, 80 selfcheck_mismatch (selfcheck)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 1296 | wrong_result | `mu` | `""` | `"😀"` | `(?:)` | 03 |
| 640 | wrong_result | `mu` | `""` | `"😀"` | `()` | 03 |
| 100 | wrong_result | `mu` | `""` | `"😀"` | `(?:)` | 33 |
| 78 | wrong_span | `u` | `""` | `"😀"` | `(?!.)` | 03 |
| 56 | wrong_span | `u` | `""` | `"😀"` | `(?!\S)` | 03 |
| 37 | wrong_result | `mu` | `""` | `"😀"` | `()` | 33 |
| 24 | wrong_span | `u` | `""` | `"😀"` | `(?!\W)` | 03 |
| 19 | wrong_span | `u` | `""` | `"😀"` | `(?!\D)` | 03 |

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END deno 5m results -->
