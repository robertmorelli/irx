# Oniguruma 6.9 (C library)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py oniguruma`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN oniguruma 1m results -->
### oniguruma: 1-minute smoke campaign

* 406,144 patterns, 6 tables, 56,936 distinct findings; self-check 281,792 probes, 208 mismatches, 0 engine failures
* findings by kind: 53,586 syntax_error, 3,328 wrong_result, 193 selfcheck_mismatch (selfcheck), 22 exception

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 139 | syntax_error | `u` | `""` | `"a"` | `(?:\b)*` | 04 |
| 137 | syntax_error | `u` | `""` | `"a"` | `(?:\B)*` | 04 |
| 136 | syntax_error | `u` | `""` | `"a"` | `(?:$)*` | 04 |
| 127 | syntax_error | `u` | `""` | `"a"` | `(?:^)*` | 04 |
| 100 | syntax_error | `u` | `"a"` | `""` | `(?:$)?a` | 04 |
| 97 | syntax_error | `u` | `"a"` | `""` | `(?:\b)?a` | 04 |
| 94 | syntax_error | `u` | `""` | `"a"` | `(?:\b)?` | 04 |
| 93 | syntax_error | `u` | `""` | `"a"` | `(?:\B){0,1}` | 04 |

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END oniguruma 1m results -->

<!-- BEGIN oniguruma 10m results -->
### Oniguruma 6.9 (C library): 10m campaign

* 4,104,096 patterns, 43 tables, 284,252 distinct findings; self-check 281,792 probes, 0 mismatches, 0 engine failures
* findings by kind: 273,809 syntax_error, 8,816 wrong_result, 1,426 exception, 201 timeout (batch)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 54 | syntax_error | `u` | `"a"` | `""` | `(?:\b\|a)+` | 04 |
| 47 | syntax_error | `u` | `"a"` | `""` | `(?:a\|\b)+` | 04 |
| 41 | syntax_error | `u` | `""` | `"σ"` | `(?:a\|\b)*` | 04 |
| 36 | syntax_error | `u` | `""` | `"😀"` | `(?:\b\|a)*` | 04 |
| 36 | syntax_error | `u` | `""` | `"σ"` | `(?:a\|^)*` | 04 |
| 36 | syntax_error | `u` | `""` | `"😀"` | `(?:$\|a)*` | 04 |
| 33 | syntax_error | `u` | `""` | `"😀"` | `(?:a\|^)*` | 04 |
| 31 | syntax_error | `u` | `""` | `"σ"` | `(?:^\|a)*` | 04 |

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END oniguruma 10m results -->

<!-- BEGIN oniguruma 10m triage -->
### oniguruma: 10-minute campaign triage

* New: **IRX-ONIG-1** (shared with Ruby's Onigmo): `\A(?:^a*){2,3}\z` misses `"a"`.
* **Model gaps** (most findings):
  * 273,809 syntax errors: Oniguruma 6.9.10 rejects a quantifier on a group in which some alternative is only an
    assertion (`(?:a|\b)+`, `(?:a|^)*`, `(?:a|(?=a))*`, `(?:a|\b)?`: "target of repeat operator is invalid"), while
    `(?:a\b)*` is fine. The dialect's `allow_empty_quant = false` only covers fully zero-width bodies.
  * Wrong results with `{n}?`: in Ruby syntax `a{n}?` means `(?:a{n})?`, not a lazy exact count
    (`a{2}?a` matches `"a"`). Printing a lazy exact count as `{n}` for the Ruby dialects fixes it.
* The 1,426 exceptions are Oniguruma's retry limit on exponential patterns such as `(?:a|a)+` over 23 characters.
* Self-check clean.
<!-- END oniguruma 10m triage -->
