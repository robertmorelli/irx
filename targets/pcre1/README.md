# PCRE1 8.45

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py pcre1`.
PCRE1 8.45 (Homebrew `pcre`, deprecated upstream but still embedded in many programs) through `hosts/c/pcre1_host.c`, UTF-8 + UCP. Dialect `pcre1`: PCRE2's model with the older UCP `\w` (no Mn, Pc). Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN pcre1 r10 results -->
### PCRE1 8.45: r10 campaign

* 4,752,224 patterns, 49 tables, 11,123 distinct findings
* findings by kind: 5,123 wrong_span, 4,000 wrong_result, 2,000 wrong_capture

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 166 | wrong_result | `iu` | `"ΐ"` | `""` | `\x{1FD3}` | 00 |
| 95 | wrong_span | `iu` | `"ΐ"` | `""` | `\x{1FD3}` | 00 |
| 84 | wrong_capture | `iu` | `"ΐ"` | `""` | `\x{1FD3}` | 00 |
| 62 | wrong_result | `iu` | `"ΐ"` | `""` | `[\x{401}\x{1FD3}]` | 00 |
| 58 | wrong_result | `iu` | `"ΐaΐa"` | `""` | `(?:\x{1FD3}a){1,2}` | 00 |
| 44 | wrong_result | `iu` | `"ΐaΐa"` | `"a"` | `(?:\x{1FD3}a){0,2}` | 00 |
| 37 | wrong_span | `iu` | `"a"` | `"ΐ"` | `[^ \x{1FD3}]` | 03 |
| 37 | wrong_span | `iu` | `"ΐ"` | `""` | `[\x{401}\x{1FD3}]` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END pcre1 r10 results -->

<!-- BEGIN pcre1 r2h results -->
### PCRE1 8.45: r2h campaign

* 62,453,760 patterns, 626 tables, 12,000 distinct findings; self-check 2,966,368 probes, 0 mismatches, 0 engine failures
* findings by kind: 6,000 wrong_span, 4,000 wrong_result, 2,000 wrong_capture

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 72 | wrong_result | `u` | `"aa"` | `""` | `\P{Lu}+\D` | 00 |
| 36 | wrong_span | `u` | `"aa"` | `""` | `\P{Lu}+\D` | 00 |
| 34 | wrong_result | `u` | `"aa"` | `""` | `\P{Zs}+\D` | 00 |
| 32 | wrong_result | `u` | `"aa"` | `""` | `\D+\P{Pc}` | 00 |
| 32 | wrong_result | `u` | `"aa"` | `""` | `\D+\P{Zs}` | 00 |
| 32 | wrong_result | `u` | `"a"` | `""` | `\D*\P{Po}` | 00 |
| 30 | wrong_result | `u` | `"aa"` | `""` | `\P{Lu}+\P{Cc}` | 00 |
| 30 | wrong_result | `u` | `"aa"` | `""` | `\P{Po}+\D` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END pcre1 r2h results -->
<!-- BEGIN pcre1 r2h triage -->
### pcre1: r2h (2-hour) campaign triage

PCRE1 8.45 (interpreter), with the old-Unicode pool fix; self-check clean.

* No new IDs beyond those found on `pcre1-jit`: IRX-PCRE2-4's shape (loops over negated properties/shorthands, also `\w{0,1}\p{Pc}`), about 11,900; IRX-PCRE1-2 (atomic/possessive groups around empty captures), about 90; IRX-PCRE1-1 (caseless non-ASCII lookahead start), 8.
<!-- END pcre1 r2h triage -->
