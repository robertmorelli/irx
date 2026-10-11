# PHP 8.5 preg_* (PCRE2 + JIT)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py php-pcre2`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN php-pcre2 1m results -->
### php-pcre2: 1-minute smoke campaign

* 1,627,136 patterns, 18 tables, 3,214 distinct findings; self-check 281,792 probes, 0 mismatches, 0 engine failures
* findings by kind: 2,844 exception, 370 wrong_result

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 4 | wrong_result | `u` | `"a"` | `""` | `(?<!(?:(?:)\|a)$)a` | 00 |
| 4 | exception | `u` | `""` | `"aaaaaaaaaaaaaaaaaa "` | `(?:a(?:){0,1})*` | 08 |
| 4 | wrong_result | `u` | `"a"` | `""` | `(?<!(?:)(?:$\|a))a` | 00 |
| 4 | wrong_result | `u` | `"a"` | `""` | `(?<!a?$)a` | 00 |
| 3 | exception | `u` | `""` | `"aaaaaaaaaaſΣk "` | `(?:(?:a\|(?:)){0,2})+` | 08 |
| 3 | exception | `u` | `""` | `"aaaaaaaaaaςſΣk "` | `(?:(?:a\|(?:)){0,2})*` | 08 |
| 2 | exception | `u` | `"aaaaaa"` | `""` | `(?:(?:(?:(?:)?){0,3}a){2,}){3,3}` | 08 |
| 2 | exception | `u` | `""` | `"aaaaaaaaΣk "` | `(?:(?:a*){0,2})*` | 08 |

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END php-pcre2 1m results -->

<!-- BEGIN php-pcre2 10m results -->
### PHP 8.5 preg_* (PCRE2 + JIT): 10m campaign

* 10,929,184 patterns, 111 tables, 70,932 distinct findings; self-check 281,792 probes, 0 mismatches, 0 engine failures
* findings by kind: 68,592 exception, 2,336 wrong_result, 4 timeout (batch)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 17 | exception | `u` | `""` | `"aaaaaaaaaaςΣà_Σ_Aàb.ı"` | `(?:(?:a\|(?:)){0,2})*` | 08 |
| 15 | exception | `u` | `""` | `"aaaaaaaaaaςſΣk "` | `(?:(?:a\|(?:)){0,2})*` | 08 |
| 11 | wrong_result | `u` | `"a"` | `""` | `(?<!(?:)(?:a\|$))a` | 00 |
| 10 | exception | `u` | `""` | `"aaaaaaaaaaςΣà_Σ_Aàb.ı"` | `(?:(?:a\|(?:)){0,2})+` | 08 |
| 8 | exception | `u` | `""` | `"aaaaaaaaaaaaaaaaaa "` | `(?:a(?:)?)*` | 08 |
| 7 | wrong_result | `u` | `"a"` | `""` | `(?<!a?\B)a` | 00 |
| 6 | wrong_result | `u` | `"a"` | `""` | `(?<!(?:)(?:\B\|a))a` | 00 |
| 6 | exception | `u` | `""` | `"aaaaaaaaaaςſΣk "` | `(?:(?:a\|(?:)){0,2})+` | 08 |

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END php-pcre2 10m results -->

<!-- BEGIN php-pcre2 10m triage -->
### php-pcre2: 10-minute campaign triage

* Nothing new: the 2,336 wrong results are IRX-PCRE2-1 (PHP enables the PCRE2 JIT). The run showed the family is
  wider than recorded: positive lookbehinds and `\b`/`\B` also trigger it (`(?<=a?\b)a` misses `"a"`), so the
  ledger row has been widened.
* The 68,592 exceptions are PHP's `pcre.backtrack_limit` / JIT stack on exponential patterns
  (`(?:(?:.|.){3})+` over long subjects). PHP returns `false` and the host reports an exception.
* Self-check clean; 10.9 M cases.
<!-- END php-pcre2 10m triage -->
