# V8 15.0 (Deno 2.9.7) - older V8, excluded from the ledger

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py deno`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN deno 1m results -->
### deno: 1-minute smoke campaign

* 433,792 patterns, 6 tables, 1,178 distinct findings; self-check 1,628,352 probes, 80 mismatches, 0 engine failures
* findings by kind: 1,048 wrong_result, 130 timeout (batch), 80 selfcheck_mismatch (selfcheck)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 201 | wrong_result | `mu` | `""` | `"😀"` | `(?:)` | 03 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END deno 1m results -->

<!-- BEGIN deno 10m results -->
### V8 15.0 (Deno 2.9.7) - older V8, excluded from the ledger: 10m campaign

* 3,826,112 patterns, 40 tables, 31,116 distinct findings; self-check 1,628,352 probes, 80 mismatches, 0 engine failures
* findings by kind: 29,827 wrong_result, 1,289 timeout (batch), 80 selfcheck_mismatch (selfcheck)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 2434 | wrong_result | `mu` | `""` | `"😀"` | `(?:)` | 03 |
| 1442 | wrong_result | `mu` | `""` | `"😀"` | `(?:)` | 33 |
| 4 | wrong_result | `mu` | `"a\raa😀a"` | `"😀"` | `(?:a\Wa)*` | 03 |
| 3 | wrong_result | `s` | `"aaaaaaaa"` | `"aaaaaaaaa"` | `(?:[^\u00DF].)*` | 33 |
| 3 | wrong_result | `s` | `"aaaaaaaa"` | `"aaaaaaaaa"` | `(?:[^\u00DF].)*` | 03 |
| 2 | wrong_result | `mu` | `"\ra.a"` | `"😀"` | `(?:\Wa)*` | 33 |
| 2 | wrong_result | `s` | `"aaaaaaaa"` | `"aaaaaaİaa"` | `(?:[^\u212A].){0,}` | 03 |
| 2 | wrong_result | `s` | `"aaaaaaaa"` | `"aaaaaaİaa"` | `(?:[^\u212A].){0,}` | 33 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END deno 10m results -->

<!-- BEGIN deno 10m triage -->
### deno: 10-minute campaign triage

* New (excluded from the ledger: not in d8 15.5 or Node's V8 14.1): after a warm-up match, V8 15.0's compiled
  regexp accepts odd lengths for a repeated pair of negated classes when the second excludes only non-ASCII
  (or everything, as `.` under `s` does):
  `const r = /^(?:[^a][^K])*$/; r.test("xx"); r.test("xxx")` → `true` (first call alone: `false`).
  `--regexp-interpret-all` or `--no-regexp-tier-up` fixes it, so it is in the native tier. `[^a][^b]` and
  `[^a][^\n]` are fine.
* The `mu`/`mv` findings with `😀` (`(?:)` accepting `"😀"`) and the `\B[^]*` self-check mismatches are the
  surrogate-pair family (IRX-V8-3, V8-2).
* 1,289 timeouts: load-induced, as for Bun.
<!-- END deno 10m triage -->

<!-- BEGIN deno 5m results -->
### V8 15.0 (Deno 2.9.7) - older V8, excluded from the ledger: 5m campaign

* 1,001,024 patterns, 12 tables, 10,852 distinct findings; self-check 1,628,352 probes, 80 mismatches, 0 engine failures
* findings by kind: 10,179 wrong_result, 372 timeout (batch), 301 wrong_span, 80 selfcheck_mismatch (selfcheck)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 1296 | wrong_result | `mu` | `""` | `"😀"` | `(?:)` | 03 |
| 640 | wrong_result | `mu` | `""` | `"😀"` | `()` | 03 |
| 100 | wrong_result | `mu` | `""` | `"😀"` | `(?:)` | 33 |
| 78 | wrong_span | `u` | `""` | `"😀"` | `(?!.)` | 03 |
| 56 | wrong_span | `u` | `""` | `"😀"` | `(?!\S)` | 03 |
| 37 | wrong_result | `mu` | `""` | `"😀"` | `()` | 33 |
| 24 | wrong_span | `u` | `""` | `"😀"` | `(?!\W)` | 03 |
| 19 | wrong_span | `u` | `""` | `"😀"` | `(?!\D)` | 03 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END deno 5m results -->

<!-- BEGIN deno 30m results -->
### V8 15.0 (Deno 2.9.7) - older V8, excluded from the ledger: 30m campaign

* 12,852,736 patterns, 130 tables, 182,930 distinct findings; self-check 1,628,352 probes, 80 mismatches, 0 engine failures
* findings by kind: 178,082 wrong_result, 1,938 wrong_capture, 1,938 wrong_span, 971 timeout (batch), 80 selfcheck_mismatch (selfcheck), 1 tier_mismatch

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 4684 | wrong_result | `mu` | `""` | `"😀"` | `(?:)` | 03 |
| 3974 | wrong_result | `mu` | `""` | `"😀"` | `(?:)` | 33 |
| 2440 | wrong_result | `mu` | `""` | `"😀"` | `()` | 03 |
| 2106 | wrong_result | `mu` | `""` | `"😀"` | `()` | 33 |
| 45 | wrong_capture | `u` | `""` | `"😀"` | `(?!.)` | 03 |
| 45 | wrong_span | `u` | `""` | `"😀"` | `(?!.)` | 03 |
| 33 | wrong_result | `mu` | `"aa"` | `"😀"` | `(?:aa)?` | 03 |
| 21 | wrong_result | `mu` | `"ßa\ra.aka"` | `"😀"` | `(?:[^ab]a)*` | 03 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END deno 30m results -->

<!-- BEGIN deno r2h results -->
### V8 15.0 (Deno 2.9.7) - older V8, excluded from the ledger: r2h campaign

* 22,234,816 patterns, 224 tables, 13,685 distinct findings; self-check 19,969,280 probes, 7,656 mismatches, 0 engine failures
* findings by kind: 6,000 wrong_span, 4,000 wrong_result, 2,000 wrong_capture, 1,685 timeout (batch), 20 selfcheck_mismatch (selfcheck)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 798 | wrong_result | `mu` | `""` | `"𝟎"` | `(?:)` | 03 |
| 798 | wrong_result | `mu` | `""` | `"𝟎"` | `(?:)` | 33 |
| 344 | wrong_result | `mu` | `""` | `"𝟎"` | `()` | 03 |
| 344 | wrong_result | `mu` | `""` | `"𝟎"` | `()` | 33 |
| 48 | wrong_span | `u` | `"σa😀"` | `"a"` | `\B\S*` | 00 |
| 39 | wrong_span | `u` | `""` | `"aa😀"` | `\B` | 03 |
| 37 | wrong_span | `u` | `".aa😀aaa😀"` | `"a"` | `\B\S*` | 00 |
| 33 | wrong_span | `u` | `"😀a"` | `".σ_😀_b "` | `\B\S*` | 03 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END deno r2h results -->
<!-- BEGIN deno r2h triage -->
### deno: r2h (2-hour) campaign triage

* Nothing for the ledger (V8 15.0 is excluded; d8 15.5 is correct on every shape below).
* New, already fixed in d8 15.5 (Node's V8 14.1 has it too): under `u` or `v`, an inline modifier group leaks its case flag into the character classes after it. `/^(?:(?i:)[b])$/v.test("B")` → `true`, `/^(?:(?i:)[^b])$/v.test("B")` → `false`, `/^(?:(?-i:)[A-Z])$/iu.test("a")` → `false`; literals are unaffected (`(?i:)b` on `"B"` is `false`) and so is non-Unicode mode. About 3,600 findings.
* Known: the surrogate-pair family (IRX-V8-2/3; `(?:)` under `mu` accepting `"𝟎"`, `(?<!a)` spans next to astral characters, the `\B[^]*` self-check mismatches), about 4,500 findings; the native-tier repeated negated-class pair from the 10-minute triage (`(?:\P{Ll}a)*`), about 2,000; IRX-V8-5 (`\q{…}` under `vi`, also the `[…\q{k|\u{17F}}…]` self-check mismatches).
* 1,685 timeouts: load-induced.
<!-- END deno r2h triage -->
