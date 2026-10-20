# Ruby 4.0 Onigmo (ASan/UBSan)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py ruby-onigmo-asan`.
The [`ruby-onigmo`](../ruby-onigmo) target on a sanitized build: Ruby 4.0.7 built with sanitizers (`tools/build_asan_big.sh ruby`), so Onigmo runs instrumented. UBSan's alignment and function-type checks are suppressed (`tools/sanitizer/ruby.supp`): Ruby and Onigmo's bytecode load unaligned words by design. A memory error or undefined behavior aborts the host and is recorded as a crash. Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN ruby-onigmo-asan r10 results -->
### Ruby 4.0 Onigmo (ASan/UBSan): r10 campaign

* 1,273,728 patterns, 14 tables, 2,843 distinct findings
* findings by kind: 870 wrong_span, 843 wrong_result, 642 syntax_error, 428 wrong_capture, 60 timeout (batch)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 12 | syntax_error | `u` | `""` | `"a"` | `(?x:(?<=(?>(?:))))` | 04 |
| 12 | syntax_error | `u` | `"a"` | `""` | `a(?<=(?>(?:)))` | 04 |
| 11 | syntax_error | `u` | `""` | `"a"` | `(?<!(?>a))` | 04 |
| 6 | syntax_error | `u` | `"a"` | `""` | `(?x:a (?<!(?>[\-\x{430}])))` | 04 |
| 6 | syntax_error | `u` | `"ba"` | `""` | `(?<=a(?>(?:)))\|[^a\x{3C2}]a` | 04 |
| 6 | syntax_error | `u` | `""` | `"a"` | `(?<!(?>(?:)))\|(?:)` | 04 |
| 6 | syntax_error | `u` | `"aa"` | `""` | `(?<!(?>a))aa` | 04 |
| 6 | syntax_error | `u` | `"a"` | `""` | `(?<!(?>a))a` | 04 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END ruby-onigmo-asan r10 results -->

<!-- BEGIN ruby-onigmo-asan r2h results -->
### Ruby 4.0 Onigmo (ASan/UBSan): r2h campaign

* 12,061,952 patterns, 122 tables, 24,524 distinct findings; self-check 4,752,672 probes, 0 mismatches, 0 engine failures
* findings by kind: 11,770 syntax_error, 6,000 wrong_span, 4,000 wrong_result, 2,000 wrong_capture, 754 timeout (batch)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 217 | syntax_error | `u` | `""` | `"a"` | `(?<=(?>(?:)))` | 04 |
| 212 | syntax_error | `u` | `"a"` | `""` | `a(?<=(?>(?:)))` | 04 |
| 177 | syntax_error | `u` | `""` | `"a"` | `(?<!(?>a))` | 04 |
| 82 | syntax_error | `u` | `"a"` | `""` | `(?<!(?>a))a` | 04 |
| 70 | syntax_error | `u` | `""` | `"a"` | `(?:(?<!(?>(?:))))*` | 04 |
| 62 | syntax_error | `u` | `""` | `"a"` | `(?x:(?<=(?>(?:))))` | 04 |
| 50 | syntax_error | `u` | `""` | `"a"` | `\|(?<!(?>(?:)))` | 04 |
| 47 | syntax_error | `u` | `""` | `"a"` | `(?<!(?>(?:)))\|()` | 04 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END ruby-onigmo-asan r2h results -->
<!-- BEGIN ruby-onigmo-asan r2h triage -->
### ruby-onigmo-asan: r2h (2-hour) campaign triage

Ruby 4.0.7 (Onigmo; ASan/UBSan build, which also prints UBSan reports from Ruby's VM core, unrelated to regex).

* No new IDs; no ASan reports from the regex engine; self-check clean.
* Known, widened: IRX-ONIG-3 also in Onigmo: an assertion followed by `.*` under `/m` is anchored at the start (`/(?=b).*/m.match("ab")` → `nil`; `\B.*` on `"Ka"`), most wrong spans. Known: IRX-ONIG-1 (zero-width iterations in counted groups: `(?:aa|^){3}`, `(?:\P{Pd}|^){2,}`) and IRX-RUBY-1 (`(?:(){1,2}?a)+` on `"aa"`).
* Model gap, fixed: Onigmo rejects atomic groups and possessive quantifiers inside lookbehind (`(?<=(?>a))b`, `(?<=a?+)b`: "invalid pattern in look-behind"); most of the 11,770 syntax errors.
<!-- END ruby-onigmo-asan r2h triage -->
