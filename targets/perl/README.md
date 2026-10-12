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

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END perl 1m results -->

<!-- BEGIN perl 10m results -->
### Perl 5.44 (also blead via vendor/perl5): 10m campaign

* 5,433,280 patterns, 56 tables, 1,984 distinct findings; self-check 281,792 probes, 0 mismatches, 0 engine failures
* findings by kind: 1,322 timeout (batch), 662 wrong_result

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 183 | wrong_result | `mu` | `"a"` | `""` | `^\ba*` | 00 |
| 115 | wrong_result | `mu` | `"a"` | `""` | `^\b(?:(?:)\|a)` | 00 |
| 66 | wrong_result | `mu` | `"a"` | `""` | `^\b(?:a\|(?:))` | 00 |
| 38 | wrong_result | `mu` | `"a"` | `""` | `^\ba?` | 00 |
| 14 | wrong_result | `mu` | `"a"` | `""` | `^\ba{0,}` | 00 |
| 8 | wrong_result | `mu` | `"K"` | `""` | `^\b(?:(?:)\|\x{212A})` | 00 |
| 8 | wrong_result | `mu` | `"K"` | `""` | `^\b\x{212A}*` | 00 |
| 4 | wrong_result | `mu` | `"_"` | `""` | `^\b(?:[^as]\|(?:))` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END perl 10m results -->

<!-- BEGIN perl 10m triage -->
### perl: 10-minute campaign triage

* Nothing new: all 112 minimized shapes are IRX-PERL-2 (`^\ba*` under `/m`, plus variants with `(?:(?:)|a)` and
  `K`) or IRX-PERL-1 (`(?=a*)` before a character class: an empty synthetic start class).
* Self-check clean; 5.4 M cases. 1,322 timeouts: backtracking blowups, not investigated.
<!-- END perl 10m triage -->

<!-- BEGIN perl 5m results -->
### Perl 5.44 (also blead via vendor/perl5): 5m campaign

* 1,655,296 patterns, 18 tables, 519 distinct findings; self-check 281,792 probes, 0 mismatches, 0 engine failures
* findings by kind: 379 timeout (batch), 82 wrong_span, 58 wrong_result

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 8 | wrong_result | `mu` | `"a"` | `""` | `^\b(?:\|a)` | 00 |
| 4 | wrong_result | `mu` | `"a"` | `""` | `^\b(?:(?:)\|a)` | 00 |
| 2 | wrong_result | `imu` | `"ſ"` | `""` | `^\bs?` | 00 |
| 2 | wrong_result | `u` | `"ſ"` | `""` | `(?=a?)\w(?:a\|(?:))` | 00 |
| 2 | wrong_span | `u` | `" "` | `"ka"` | `(?=a*).` | 02 |
| 2 | wrong_result | `imu` | `"ſ"` | `""` | `^\b[k-s]?` | 00 |
| 2 | wrong_result | `u` | `"Kaaa"` | `""` | `(?:(?=a*)\Da){1,2}` | 00 |
| 2 | wrong_result | `u` | `"😀aa"` | `""` | `(?:(?=a?)[^A\x{E0}]){3,}` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END perl 5m results -->

<!-- BEGIN perl 30m results -->
### Perl 5.44 (also blead via vendor/perl5): 30m campaign

* 15,646,080 patterns, 158 tables, 6,950 distinct findings; self-check 281,792 probes, 0 mismatches, 0 engine failures
* findings by kind: 3,620 wrong_result, 1,505 timeout (batch), 974 wrong_capture, 851 wrong_span

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 1044 | wrong_result | `mu` | `"a"` | `""` | `^\ba*` | 00 |
| 243 | wrong_result | `mu` | `"a"` | `""` | `^\b(?:()\|a)` | 00 |
| 220 | wrong_result | `mu` | `"a"` | `""` | `^\b(?:(?:)\|a)` | 00 |
| 185 | wrong_result | `mu` | `"a"` | `""` | `^\b(?:\|a)` | 00 |
| 185 | wrong_result | `mu` | `"a"` | `""` | `^\b(?:a\|)` | 00 |
| 180 | wrong_result | `mu` | `"a"` | `""` | `^\ba?` | 00 |
| 164 | wrong_result | `mu` | `"a"` | `""` | `^\b(?:a\|(?:))` | 00 |
| 162 | wrong_result | `mu` | `"a"` | `""` | `^\b(?:a\|())` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END perl 30m results -->

<!-- BEGIN perl long-10m results -->
### Perl 5.44 (also blead via vendor/perl5): long-10m campaign

* 178,336 patterns, 3 tables, 19 distinct findings; self-check 281,792 probes, 0 mismatches, 0 engine failures
* findings by kind: 9 wrong_span, 8 wrong_capture, 1 long_result, 1 timeout (batch)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 2 | wrong_span | `u` | `"-Kké_"` | `"-ſ0é"` | `(?:(?=a?)\D){1,}` | 02 |
| 2 | wrong_capture | `u` | `"-Kké_"` | `"-ſ0é"` | `(?:(?=a?)\D){1,}` | 02 |
| 1 | long_result | `u` | `"-Kké_"` | `"-ſ0é"` | `(?:(?=a?)\D){1,}` | 00 |
| 1 | wrong_capture | `u` | `"-Kké_"` | `"-ſ0é"` | `(?=a?)\D+` | 02 |
| 1 | wrong_span | `u` | `"😀A\nàk\rk"` | `"😀Aà😀k\rk"` | `(?=a?)[^\x{E0}\x{D}](?:()\|[^\x{2028}\x{1F600}])` | 02 |
| 1 | wrong_span | `u` | `"😀A\nàk\rk"` | `"😀Aà😀k\rk"` | `(?=a{0,1}).(?:\|[^b\x{1F600}])` | 02 |
| 1 | wrong_capture | `u` | `"😀A\nàk\rk"` | `"😀Aà😀k\rk"` | `(?=a?)[^\x{E0}\x{D}](?:()\|[^\x{2028}\x{1F600}])` | 02 |
| 1 | wrong_capture | `u` | `"😀A\nàk\rk"` | `"😀Aà😀k\rk"` | `(?=a{0,1}).(?:\|[^b\x{1F600}])` | 02 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END perl long-10m results -->
