# RE2

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py re2`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN re2 1m results -->
### re2: 1-minute smoke campaign

* 802,048 patterns, 10 tables, 50,242 distinct findings; self-check 281,792 probes, 11,160 mismatches, 0 engine failures
* findings by kind: 50,242 wrong_result, 190 selfcheck_mismatch (selfcheck)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 22 | wrong_result | `u` | `"ſ"` | `""` | `\w` | 00 |
| 19 | wrong_result | `u` | `"Σ"` | `""` | `\w` | 00 |
| 17 | wrong_result | `u` | `"ſ"` | `"aa"` | `\w` | 00 |
| 13 | wrong_result | `u` | `"aſ"` | `""` | `a\w` | 00 |
| 12 | wrong_result | `u` | `"aaaaaaaſ"` | `"a"` | `(?:a\w)*` | 00 |
| 12 | wrong_result | `u` | `"aſ"` | `""` | `a\B.` | 00 |
| 10 | wrong_result | `u` | `"aaaaΣaaa"` | `"a"` | `(?:\wa)*` | 00 |
| 9 | wrong_result | `u` | `"aaaaaaaſ"` | `"a"` | `(?:a\B.)*` | 00 |

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END re2 1m results -->

<!-- BEGIN re2 10m results -->
### RE2: 10m campaign

* 18,902,048 patterns, 191 tables, 8 distinct findings; self-check 339,984 probes, 0 mismatches, 0 engine failures
* findings by kind: 8 wrong_result

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 1 | wrong_result | `u` | `"a"` | `"ſ"` | `a\|[sS]` | 03 |
| 1 | wrong_result | `u` | `""` | `"ſ"` | `(?:[sS]\|a){0,}` | 33 |
| 1 | wrong_result | `u` | `""` | `"ſ"` | `(?:[sS]\|a)*` | 03 |
| 1 | wrong_result | `u` | `""` | `"ſ"` | `(?:[sS]\|a)*` | 33 |
| 1 | wrong_result | `u` | `""` | `"ſ"` | `(?:)\|[sS]\|a` | 33 |
| 1 | wrong_result | `u` | `""` | `"ſ"` | `(?:[sS]\|a){0,}` | 03 |
| 1 | wrong_result | `u` | `"a"` | `"ſ"` | `a\|[sS]` | 33 |
| 1 | wrong_result | `u` | `""` | `"ſ"` | `(?:)\|[sS]\|a` | 03 |

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END re2 10m results -->

<!-- BEGIN re2 10m triage -->
### re2: 10-minute campaign triage

* New: **IRX-RE2-1**. All 8 findings: without the `i` flag, `a|[sS]` matches `"ſ"` and `b|[kK]` matches `"K"`.
* Self-check clean; 18.9 M cases; no timeouts.
<!-- END re2 10m triage -->

<!-- BEGIN re2 5m results -->
### RE2: 5m campaign

* 8,101,024 patterns, 83 tables, 1,664 distinct findings; self-check 339,984 probes, 0 mismatches, 0 engine failures
* findings by kind: 1,652 wrong_span, 12 wrong_result

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 591 | wrong_span | `u` | `""` | `"aK"` | `\B` | 03 |
| 208 | wrong_span | `u` | `""` | `"aİ"` | `\B` | 03 |
| 34 | wrong_span | `u` | `""` | `"aΣ"` | `\B` | 03 |
| 21 | wrong_span | `u` | `""` | `"aσ"` | `\B` | 03 |
| 16 | wrong_span | `u` | `"aa"` | `"aΣ"` | `\B\|aa` | 03 |
| 13 | wrong_span | `u` | `"aa"` | `"aΣ"` | `aa\|\B` | 03 |
| 10 | wrong_span | `u` | `"aaa"` | `"aΣ"` | `\B\|aaa` | 03 |
| 8 | wrong_span | `u` | `"0a"` | `"aİ"` | `\B\|\da` | 03 |

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END re2 5m results -->
