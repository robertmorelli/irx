# GraalJS 25.4 (TRegex)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py graaljs`.
GraalJS community (native image) from its GitHub release, unpacked into `vendor/graaljs`. Its regexps run on TRegex, an independent engine (automaton-based with a backtracking fallback), not a port of Irregexp or YARR. Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN graaljs r10 results -->
### GraalJS 25.4 (TRegex): r10 campaign

* 664,000 patterns, 8 tables, 305 distinct findings
* findings by kind: 173 timeout (batch), 72 wrong_span, 36 wrong_result, 24 wrong_capture

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 3 | wrong_span | `` | `"aa"` | `""` | `(?:a(?:(?:a\B){0,2}){1,2}){2,}` | 00 |
| 2 | wrong_result | `` | `"aa"` | `""` | `(?:a(?:(?:a\B){0,2}){1,2}){2,}` | 00 |
| 2 | wrong_span | `` | `"aaa"` | `""` | `(?:a(?:(?:\B\|\B\|a)?\|(?:)){1,2}){3,3}` | 00 |
| 2 | wrong_span | `` | `"aaaa"` | `""` | `(?:a(?:(?:a*)+\|(?:\b){1,1}\B){1,2}){3}` | 00 |
| 2 | wrong_result | `mu` | `"ΐЁ aa"` | `""` | `(?:\W(?:(?:\b$a)*\|\b){1,2}){2,}\P{So}{3,3}` | 00 |
| 2 | wrong_span | `` | `"aaa"` | `""` | `(?:a(?:(?:a(?:\b()\|\B))*){1,2}){3}` | 00 |
| 2 | wrong_span | `` | `"ΐaaa"` | `""` | `(?:\B[^\u2126\u03D1](?:(?:(?:(?:)a){3,}){0,3}\|a*){1,2}){3,}` | 00 |
| 2 | wrong_span | `` | `"aaaaaa"` | `""` | `(?:aa(?:(?:a*)+\|(?:\b){1,1}\B){1,2}){3}` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END graaljs r10 results -->

<!-- BEGIN graaljs r2h results -->
### GraalJS 25.4 (TRegex): r2h campaign

* 8,417,920 patterns, 86 tables, 16,444 distinct findings; self-check 21,012,224 probes, 14,976 mismatches, 0 engine failures
* findings by kind: 8,000 wrong_span, 4,000 wrong_result, 2,444 timeout (batch), 2,000 wrong_capture, 60 selfcheck_mismatch (selfcheck)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 822 | wrong_span | `u` | `""` | `"aaa𝟎 "` | `\B` | 03 |
| 481 | wrong_span | `u` | `""` | `"aa①𝟎"` | `\B` | 03 |
| 475 | wrong_span | `u` | `""` | `"aaa𝟎"` | `\B` | 03 |
| 425 | wrong_result | `u` | `"𝟎"` | `""` | `\B.` | 00 |
| 328 | wrong_span | `u` | `"𝟎"` | `""` | `\B.` | 00 |
| 302 | wrong_span | `u` | `""` | `"𝟎"` | `\B` | 03 |
| 147 | wrong_capture | `u` | `"𝟎"` | `""` | `\B.` | 00 |
| 86 | wrong_result | `u` | `"𝟎"` | `""` | `\B\D` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END graaljs r2h results -->
<!-- BEGIN graaljs r2h triage -->
### graaljs: r2h (2-hour) campaign triage

GraalJS 25.4.4.1.1 (TRegex). Rerun from the start after the 2026-10-15 OS update.

* New: IRX-GRAAL-2 (under `u`/`v`, `\b` and `\B` both fail next to an astral character: `/^\B/u.test("😀")` → `false`), about 13,300 findings and all 14,976 self-check mismatches; IRX-GRAAL-3 (under `iv`, `[\W--\p{L}]` keeps `Σ`), about 370.
* Known: IRX-GRAAL-1's shape (nested counted loops with an optional inner group around `\b`/`\B`, e.g. `(?:a(?:(?:a\b){0,2}){1,2}){2,2}` fails on `"aa"`), about 360.
* 2,444 batch timeouts.
<!-- END graaljs r2h triage -->
