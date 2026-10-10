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
