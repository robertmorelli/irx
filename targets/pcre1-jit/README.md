# PCRE1 8.45 JIT

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py pcre1-jit`.
PCRE1 8.45 (Homebrew `pcre`, deprecated upstream but still embedded in many programs) through `hosts/c/pcre1_host.c`, UTF-8 + UCP, JIT-compiled with `pcre_study`. Dialect `pcre1`: PCRE2's model with the older UCP `\w` (no Mn, Pc). Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN pcre1-jit r2h results -->
### PCRE1 8.45 JIT: r2h campaign

* 61,559,392 patterns, 617 tables, 12,008 distinct findings; self-check 3,013,952 probes, 64 mismatches, 0 engine failures
* findings by kind: 6,000 wrong_span, 4,000 wrong_result, 2,000 wrong_capture, 20 selfcheck_mismatch (selfcheck), 8 timeout (batch)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 72 | wrong_result | `u` | `"aa"` | `""` | `\P{Lu}+\D` | 00 |
| 37 | wrong_span | `u` | `"aa"` | `""` | `\P{Lu}+\D` | 00 |
| 34 | wrong_result | `u` | `"aa"` | `""` | `\P{Zs}+\D` | 00 |
| 32 | wrong_result | `u` | `"aa"` | `""` | `\D+\P{Pc}` | 00 |
| 32 | wrong_result | `u` | `"a"` | `""` | `\D*\P{Po}` | 00 |
| 32 | wrong_result | `u` | `"aa"` | `""` | `\D+\P{Zs}` | 00 |
| 30 | wrong_result | `u` | `"aa"` | `""` | `\P{Po}+\D` | 00 |
| 30 | wrong_result | `u` | `"aa"` | `""` | `\P{Lu}+\P{Cc}` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END pcre1-jit r2h results -->
<!-- BEGIN pcre1-jit r2h triage -->
### pcre1-jit: r2h (2-hour) campaign triage

PCRE1 8.45 with JIT (with the old-Unicode pool fix).

* New: IRX-PCRE1-1 (caseless non-ASCII lookahead at the pattern start: the unanchored search skips positions by UTF-8 lead byte, `(?=\x{401}).` never finds ё), IRX-PCRE1-2 (`(?>(?:.|())*)a` matches `"a"`); both also without JIT.
* Known: IRX-PCRE2-4's shape (loops over negated properties/shorthands), most findings. Self-check mismatches: PCRE1's older Unicode data (fixed in the dialect after the run started).
<!-- END pcre1-jit r2h triage -->
