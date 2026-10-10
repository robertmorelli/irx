# Perl 5.44 (also blead via vendor/perl5)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py perl`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN perl 1m results -->
### perl: 1-minute smoke campaign

* 757,856 patterns, 9 tables, 156 distinct findings; self-check 281,792 probes, 0 mismatches, 0 engine failures
* findings by kind: 100 timeout (batch), 56 wrong_result

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 14 | wrong_result | `mu` | `"a"` | `""` | `^\b(?:(?:)\|a)` | 00 |
| 10 | wrong_result | `mu` | `"a"` | `""` | `^\b(?:a\|(?:))` | 00 |
| 6 | wrong_result | `mu` | `"a"` | `""` | `^\ba*` | 00 |
| 2 | wrong_result | `imu` | `"ſ"` | `""` | `^\b(?:(?:)\|[k-s])` | 00 |
| 2 | wrong_result | `mu` | `"a"` | `""` | `^\ba{0,1}` | 00 |
| 2 | wrong_result | `mu` | `"a"` | `""` | `^\ba?` | 00 |
| 2 | wrong_result | `iu` | `"ſ"` | `""` | `(?=a{0,1})a*[k-s]` | 00 |
| 2 | wrong_result | `mu` | `"a"` | `"aa"` | `^\b(?:\ba)*` | 00 |

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END perl 1m results -->
