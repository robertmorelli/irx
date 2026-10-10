# Boa (boa_cli)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py boa`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN boa results -->
## Boa campaign results

10-minute campaign, 8 cores, edit-distance-5 A/R pairs, via `tools/bridge.py` with object-literal batches.

* 635,328 patterns over 8 tables; self-check: 744,480 probes, 7,112 mismatches, all IRX-BOA-2 / IRX-BOA-3.
* 5,896 wrong results: IRX-BOA-3…6 (case folding, `\b` under `iv`, nested loops with `(?:){0,1}`, `v` complements).
* 2,186 timeouts (not triaged).

Counts are distinct findings; one bug produces many distinct regexes. Shapes were checked on the minimized subset triaged during the campaign, and representatives were confirmed against d8 15.5 and the relation model.
<!-- END boa results -->

<!-- BEGIN boa 1m results -->
### boa: 1-minute smoke campaign

* 53,248 patterns, 2 tables, 208 distinct findings; self-check 1,628,352 probes, 9,252 mismatches, 0 engine failures
* findings by kind: 208 timeout (batch), 182 selfcheck_mismatch (selfcheck)

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END boa 1m results -->

<!-- BEGIN boa 10m results -->
### Boa (boa_cli): 10m campaign

* 692,672 patterns, 8 tables, 2,296 distinct findings; self-check 1,628,352 probes, 9,252 mismatches, 0 engine failures
* findings by kind: 2,212 timeout (batch), 182 selfcheck_mismatch (selfcheck), 84 wrong_result

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 4 | wrong_result | `` | `"aa"` | `""` | `(?:(?:a+)+){2,2}` | 00 |
| 3 | wrong_result | `` | `"aa"` | `""` | `(?:(?:a{1,})+){2,2}` | 00 |
| 2 | wrong_result | `` | `"aa"` | `""` | `(?:(?:a+)+){2,}` | 00 |
| 2 | wrong_result | `` | `"aa"` | `""` | `(?:(?:a*a)+){2}` | 00 |
| 2 | wrong_result | `` | `"\naa"` | `"a"` | `(?:(?:\sa+?){1,1})*` | 00 |
| 2 | wrong_result | `` | `"aa"` | `""` | `(?:(?:a+){1,1}){2}` | 00 |
| 2 | wrong_result | `` | `"aa"` | `""` | `(?:(?:a+){1,1}){2,}` | 00 |
| 2 | wrong_result | `` | `"aa"` | `""` | `(?:(?:a*a){1,}){2,2}` | 00 |

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END boa 10m results -->

<!-- BEGIN boa 10m triage -->
### boa: 10-minute campaign triage

* New: **IRX-BOA-7** (`(?:(?:a+)+){2}` misses `"aa"`; all 84 wrong results minimize to this family) and
  **IRX-BOA-8** (`(?:(?:a|)*)*b` hangs on `"a"`).
* The 2,212 timeouts come from IRX-BOA-8-style hangs: a timed-out batch is recorded under its first case,
  which is fast on its own; timing the batch's cases one at a time finds the hanging one.
  Only ~18% of cases executed because hung batches are killed and restarted.
* Self-check mismatches are the known IRX-BOA-2/3/4 family.
<!-- END boa 10m triage -->
