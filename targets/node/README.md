# V8 14.1 (Node 25.8) - older V8, excluded from the ledger

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py node`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN node 1m results -->
### node: 1-minute smoke campaign

* 437,888 patterns, 6 tables, 2,245 distinct findings; self-check 1,628,352 probes, 80 mismatches, 0 engine failures
* findings by kind: 2,098 wrong_result, 147 timeout (batch), 80 selfcheck_mismatch (selfcheck)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 200 | wrong_result | `mu` | `""` | `"😀"` | `(?:)` | 03 |

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END node 1m results -->

<!-- BEGIN node 10m results -->
### V8 14.1 (Node 25.8) - older V8, excluded from the ledger: 10m campaign

* 3,896,768 patterns, 40 tables, 33,595 distinct findings; self-check 1,628,352 probes, 80 mismatches, 0 engine failures
* findings by kind: 32,286 wrong_result, 1,309 timeout (batch), 80 selfcheck_mismatch (selfcheck)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 2233 | wrong_result | `mu` | `""` | `"😀"` | `(?:)` | 03 |
| 642 | wrong_result | `mu` | `""` | `"😀"` | `(?:)` | 33 |
| 2 | wrong_result | `mu` | `"😀a"` | `"😀"` | `(?:\Wa)*` | 03 |
| 2 | wrong_result | `mu` | `"aaaa"` | `"😀"` | `(?:aa){0,2}` | 33 |
| 1 | wrong_result | `mu` | `"aaaa"` | `"😀"` | `(?:aa){0,2}` | 03 |
| 1 | wrong_result | `mu` | `"\ra😀a"` | `"😀"` | `(?:\Wa)*` | 33 |
| 1 | wrong_result | `mu` | `"\raa.aa"` | `"😀"` | `(?:\Waa)*` | 03 |
| 1 | wrong_result | `imv` | `"ak"` | `"😀"` | `(?:a[[A-Z]--[\u{1F600}a]])*` | 33 |

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END node 10m results -->

<!-- BEGIN node 10m triage -->
### node: 10-minute campaign triage

* Nothing new. All 32,286 wrong results have the `m` flag, `u` or `v`, and an astral subject (`😀`): the V8
  surrogate-pair family (V8-2/IRX-V8-3), where a match starts inside a surrogate pair. The 80 self-check mismatches
  (`\B[^]*`) are the same family.
* Unlike Deno's V8 15.0, Node's V8 14.1 does not have the warm-up negated-class bug (see `targets/deno`).
* 1,309 timeouts: load-induced, as for Bun and Deno.
<!-- END node 10m triage -->
