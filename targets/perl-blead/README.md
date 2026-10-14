# Perl blead

See [`target.toml`](target.toml) for how irx drives this engine.

<!-- BEGIN perl-blead blead1h results -->
### Perl blead: blead1h campaign

* 13,969,120 patterns, 141 tables, 13,631 distinct findings; self-check 4,820,512 probes, 528 mismatches, 0 engine failures
* findings by kind: 6,000 wrong_span, 4,000 wrong_result, 2,000 wrong_capture, 1,545 timeout (batch), 86 tier_mismatch, 24 selfcheck_mismatch (selfcheck)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 77 | wrong_span | `u` | `""` | `"a"` | `(?<=(?>(?:)))` | 02 |
| 77 | wrong_result | `mu` | `"a"` | `""` | `^\ba*` | 00 |
| 71 | wrong_span | `u` | `"ΐ"` | `""` | `[\x{390}\x{1FD3}]` | 00 |
| 58 | wrong_result | `u` | `"ΐ"` | `""` | `[\x{390}\x{1FD3}]` | 00 |
| 52 | wrong_result | `u` | `""` | `"a"` | `(?<=(?>(?:)))` | 00 |
| 38 | wrong_result | `mu` | `"a"` | `""` | `^\b(?:()\|a)` | 00 |
| 38 | wrong_result | `u` | `"a"` | `""` | `(?<=(?>(?:)))a` | 00 |
| 37 | wrong_capture | `u` | `"ΐ"` | `""` | `[\x{390}\x{1FD3}]` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END perl-blead blead1h results -->
<!-- BEGIN perl-blead blead1h triage -->
### perl-blead: 1-hour campaign triage (blead `90cd16d`, Unicode 18.0)

* No new Perl bugs. Known bugs account for the findings:
  * IRX-PERL-8 (state carried between matches): about 8,900. Atomic groups and possessive quantifiers inside lookarounds go wrong after earlier matches in the same process; sampled findings agree with the model in a fresh process. New variant: a positive lookbehind fails, e.g. `(?<=(?>(?:)))a`.
  * IRX-PERL-6 (`[\x{390}\x{1FD3}]` matches neither): about 1,460, plus 16 self-check mismatches.
  * IRX-PERL-1 (lookahead start class): about 800. IRX-PERL-2 (`^\b` under /m): about 350. IRX-PERL-4 (captures from a failed negative lookahead): a handful.
* Unicode version skew: 465 findings and 512 self-check mismatches are `\X` on a virama before a consonant with no consonant before it (blead's Unicode 18.0 keeps them in one cluster; the model and Perl 5.44 use Unicode 17).
* Model gap, fixed: the oracle took a backtracking search that ran out of steps for "no match", so deeply nested empty loops such as `(?:a(?:(?:(?:(?>a)|(?:)*)+){1,2})+){3}` on `"aaa"` were reported. It now has no answer and the case is skipped.
* 1,545 timeouts: batches over the deadline (Perl is the slowest host).
<!-- END perl-blead blead1h triage -->

<!-- BEGIN perl-blead blead10h results -->
### Perl blead: blead10h campaign

* 119,961,440 patterns, 1201 tables, 19,489 distinct findings; self-check 4,820,512 probes, 528 mismatches, 0 engine failures
* findings by kind: 6,907 timeout (batch), 6,000 wrong_span, 4,000 wrong_result, 2,000 wrong_capture, 582 tier_mismatch, 24 selfcheck_mismatch (selfcheck)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 77 | wrong_span | `u` | `""` | `"a"` | `(?<=(?>(?:)))` | 02 |
| 77 | wrong_result | `mu` | `"a"` | `""` | `^\ba*` | 00 |
| 76 | wrong_result | `u` | `"ΐ"` | `""` | `[\x{390}\x{1FD3}]` | 00 |
| 71 | wrong_span | `u` | `"ΐ"` | `""` | `[\x{390}\x{1FD3}]` | 00 |
| 52 | wrong_result | `u` | `""` | `"a"` | `(?<=(?>(?:)))` | 00 |
| 38 | wrong_result | `mu` | `"a"` | `""` | `^\b(?:()\|a)` | 00 |
| 38 | wrong_result | `u` | `"a"` | `""` | `(?<=(?>(?:)))a` | 00 |
| 37 | wrong_capture | `u` | `"ΐ"` | `""` | `[\x{390}\x{1FD3}]` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END perl-blead blead10h results -->
<!-- BEGIN perl-blead blead10h triage -->
### perl-blead: 10-hour campaign triage (blead `90cd16d`, Unicode 18.0)

* No new Perl bugs. Each of the 2,354 distinct minimized cases was rerun alone in a fresh blead process; every one that still fails there is a known bug:
  * IRX-PERL-1 (nullable lookahead body, e.g. `(?=a?)\wa`): 541 cases.
  * IRX-PERL-2 (`^\b` under /m): 339. IRX-PERL-6 (`[\x{390}\x{1FD3}]`): 243, plus 16 self-check mismatches. IRX-PERL-4 (captures from a failed negative lookahead, e.g. `(?!(a)a)`): 24.
  * IRX-PERL-8 (state carried between matches): the rest, about 10,700 findings including all 582 tier mismatches; they fail only after earlier matches in the same process.
* Unicode version skew: `\X` on a virama before a consonant (blead's Unicode 18.0), about 650 findings and 512 self-check mismatches.
* Model gap, fixed: Perl's WHILEM counts an iteration before its empty-match check, so the iteration that reaches a loop's minimum also ends the loop when it matched empty (`(?:^|.){2,3}a` on `"baa"` is `[0,3)`); the model only stopped after the minimum (findings 11532, 11561). PCRE2, checked alongside, unrolls bounded loops and has no empty check there (`[0,2)`); now modelled too.
* 6,907 timeouts: batches over the deadline under heavy machine load.
<!-- END perl-blead blead10h triage -->
