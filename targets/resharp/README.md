# RE# (resharp)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py resharp`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN resharp 1m results -->
### resharp: 1-minute smoke campaign

* 104,096 patterns, 3 tables, 48,596 distinct findings; self-check 281,792 probes, 39,008 mismatches, 0 engine failures
* findings by kind: 43,046 syntax_error, 5,550 wrong_result, 141 syntax_error (selfcheck), 54 selfcheck_mismatch (selfcheck)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 219 | syntax_error | `u` | `""` | `"a"` | `(?:)*?` | 04 |
| 191 | syntax_error | `u` | `"a"` | `""` | `a+?` | 04 |
| 141 | syntax_error | `u` | `""` | `"a"` | `(?:){0,1}?` | 04 |
| 87 | syntax_error | `u` | `""` | `"a"` | `(?:){0,}?` | 04 |
| 35 | syntax_error | `u` | `"a"` | `""` | `a{1,1}?` | 04 |
| 30 | syntax_error | `u` | `"a"` | `""` | `a(?<=(?:))` | 04 |
| 30 | wrong_result | `u` | `"aaaaaaaſ"` | `""` | `(?:a.)+` | 00 |
| 28 | syntax_error | `u` | `"aaaaaaaa"` | `"a"` | `(?:aaaa){0,2}?` | 04 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END resharp 1m results -->

<!-- BEGIN resharp 10m results -->
### RE# (resharp): 10m campaign

* 111,776 patterns, 3 tables, 110 distinct findings; self-check 289,392 probes, 0 mismatches, 0 engine failures
* findings by kind: 108 syntax_error, 2 wrong_result

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 22 | syntax_error | `mu` | `""` | `"a"` | `(?:$){0,2}` | 04 |
| 10 | syntax_error | `u` | `""` | `"a"` | `(?:(?!a)){0,2}` | 04 |
| 6 | syntax_error | `u` | `""` | `"a"` | `(?:(?=a)){0,2}` | 04 |
| 4 | syntax_error | `mu` | `"a"` | `""` | `(?:a$){1,3}` | 04 |
| 4 | syntax_error | `mu` | `"aa"` | `"a"` | `(?:aa$){0,2}` | 04 |
| 4 | syntax_error | `mu` | `"aa"` | `""` | `(?:$){0,2}aa` | 04 |
| 2 | syntax_error | `mu` | `"a"` | `""` | `(?:a$\|[^a]){1,2}` | 04 |
| 2 | syntax_error | `msu` | `"aaaaa"` | `""` | `a(?:(?:a\|$).){0,2}` | 04 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END resharp 10m results -->

<!-- BEGIN resharp 10m triage -->
### resharp: 10-minute campaign triage

* New: **IRX-RESHARP-1** (the 2 wrong results): `\A(?:a(?=b)?(?:bc)?)\z` matches `"ab"`.
* **Model gap**, the 108 syntax errors: RE# also rejects lookarounds and multi-line `$` inside *bounded* repeats
  (`(?:(?!a)){0,2}`, `(?:$){0,2}`, `(?:a(?!a)){1,3}`) and multi-line `$` in some alternations
  (`(?:a$|)(?:|a)`). The dialect only forbids them under `*`/`+`.
* Self-check clean; 112 K cases (slow compiles).
<!-- END resharp 10m triage -->

<!-- BEGIN resharp 5m results -->
### RE# (resharp): 5m campaign

* 28,672 patterns, 2 tables, 0 distinct findings; self-check 289,392 probes, 0 mismatches, 0 engine failures

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END resharp 5m results -->

<!-- BEGIN resharp long-10m results -->
### RE# (resharp): long-10m campaign

* 72,192 patterns, 2 tables, 99 distinct findings; self-check 289,392 probes, 0 mismatches, 0 engine failures
* findings by kind: 84 syntax_error, 15 wrong_span

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 4 | wrong_span | `u` | `"- kß "` | `"-K0ß"` | `\D*(?!.)` | 03 |
| 2 | wrong_span | `u` | `"- kß "` | `"-K0ß"` | `(?!\w)\D*` | 03 |
| 2 | syntax_error | `mu` | `"- kß "` | `"-K0ß"` | `(?:\|$\S)(?:(?:)\|a)` | 04 |
| 2 | syntax_error | `mu` | `"- kß "` | `"-K0ß"` | `(?:()\|$\s)[^0\x{3A3}]*` | 04 |
| 2 | syntax_error | `mu` | `"- kß "` | `"-K0ß"` | `(?:a$)?(?:\D\|())` | 04 |
| 2 | syntax_error | `u` | `"- kß "` | `"-K0ß"` | `(?!a\|[\x{E9}\x{3C3}](?=a))\D` | 04 |
| 2 | syntax_error | `mu` | `"- kß "` | `"-K0ß"` | `(?:$[^ks]\|)(?:\D\|)` | 04 |
| 2 | syntax_error | `u` | `"- kß "` | `"-K0ß"` | `(?!a\|(?=a)(?:()\|a))[^\x{17F}\x{212A}]` | 04 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END resharp long-10m results -->
