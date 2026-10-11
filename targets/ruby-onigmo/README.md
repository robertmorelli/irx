# Ruby Onigmo

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py ruby-onigmo`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN ruby-onigmo 1m results -->
### ruby-onigmo: 1-minute smoke campaign

* 428,672 patterns, 6 tables, 22,384 distinct findings; self-check 281,792 probes, 576 mismatches, 0 engine failures
* findings by kind: 17,508 wrong_result, 4,764 syntax_error, 180 selfcheck_mismatch (selfcheck), 112 timeout (batch)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 33 | wrong_result | `u` | `"Σ"` | `""` | `\w` | 00 |
| 28 | wrong_result | `u` | `"ſ"` | `""` | `\w` | 00 |
| 27 | wrong_result | `u` | `"aaaaΣaaa"` | `"a"` | `(?:\wa)*` | 00 |
| 14 | wrong_result | `u` | `"aaaaaaaſ"` | `"a"` | `(?:a\w)*` | 00 |
| 10 | wrong_result | `u` | `"ſ"` | `"aa"` | `\w` | 00 |
| 9 | wrong_result | `u` | `"aaéaaaaa"` | `"a"` | `(?:aa\wa){0,2}` | 00 |
| 9 | wrong_result | `u` | `"à"` | `""` | `\w` | 00 |
| 9 | wrong_result | `u` | `"aaéaaaaa"` | `"a"` | `(?:\wa)*` | 00 |

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END ruby-onigmo 1m results -->

<!-- BEGIN ruby-onigmo 10m results -->
### Ruby Onigmo: 10m campaign

* 4,414,336 patterns, 46 tables, 84,995 distinct findings; self-check 281,792 probes, 0 mismatches, 0 engine failures
* findings by kind: 72,052 syntax_error, 11,542 wrong_result, 1,401 timeout (batch)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 223 | syntax_error | `u` | `""` | `"a"` | `(?<=(?:)*)` | 04 |
| 147 | syntax_error | `u` | `""` | `"a"` | `(?<=(?:)?)` | 04 |
| 106 | syntax_error | `u` | `""` | `"a"` | `(?<=(?:)+)` | 04 |
| 81 | syntax_error | `u` | `"a"` | `""` | `a(?<=(?:)*)` | 04 |
| 77 | syntax_error | `u` | `"a"` | `""` | `(?<=(?:)*)a` | 04 |
| 74 | syntax_error | `u` | `"a"` | `""` | `a\|(?<!(?:)*)` | 04 |
| 66 | syntax_error | `u` | `"a"` | `""` | `(?<=(?:)?)a` | 04 |
| 62 | syntax_error | `u` | `"a"` | `""` | `(?<!(?:)*)\|a` | 04 |

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END ruby-onigmo 10m results -->

<!-- BEGIN ruby-onigmo 10m triage -->
### ruby-onigmo: 10-minute campaign triage

* New: zero-width counted iterations, folded into **IRX-ONIG-1** (`\A(?:a|^){2,3}\z` misses `"a"`).
* **Model gaps** (most findings):
  * 72,052 syntax errors: Onigmo rejects quantifiers inside lookbehind (`(?<=(?:)*)`, `(?<!(?:)?)`: "invalid
    pattern in look-behind").
  * `{n}?` means `(?:{n})?` in Ruby syntax (`(?:a{3}?a)*` matches `"a"`), as for Oniguruma.
* Self-check clean. 1,401 timeouts: backtracking blowups.
<!-- END ruby-onigmo 10m triage -->

<!-- BEGIN ruby-onigmo 5m results -->
### Ruby Onigmo: 5m campaign

* 1,605,120 patterns, 18 tables, 2,259 distinct findings; self-check 281,792 probes, 0 mismatches, 0 engine failures
* findings by kind: 1,352 wrong_result, 464 wrong_span, 443 timeout (batch)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 8 | wrong_result | `u` | `"a"` | `"_"` | `(?:^\|a){2,3}` | 00 |
| 8 | wrong_result | `u` | `"a"` | `"_"` | `(?:a\|^){2,3}` | 00 |
| 7 | wrong_result | `u` | `"a"` | `""` | `(?:a\|(?=a)){2,3}` | 00 |
| 6 | wrong_result | `u` | `"a"` | `"-"` | `(?:a\|^){2,3}` | 00 |
| 6 | wrong_result | `u` | `"a\r"` | `""` | `(?:\b\|a\s){2,2}` | 00 |
| 6 | wrong_result | `u` | `"a"` | `"-"` | `(?:^\|a){2,3}` | 00 |
| 4 | wrong_result | `u` | `"aa"` | `""` | `(?:(){1,2}?a)+` | 00 |
| 4 | wrong_result | `u` | `"a"` | `"_"` | `(?:^(?:a\|(?:))){2,3}` | 00 |

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END ruby-onigmo 5m results -->
