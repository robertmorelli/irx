# Swift Regex 6.4 (unicodeScalar semantics, simple word boundaries)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py swift-regex`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN swift-regex 1m results -->
### swift-regex: 1-minute smoke campaign

* 57,344 patterns, 2 tables, 224 distinct findings; self-check 339,984 probes, 1,664 mismatches, 0 engine failures
* findings by kind: 224 timeout (batch), 200 selfcheck_mismatch (selfcheck)

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END swift-regex 1m results -->

<!-- BEGIN swift-regex 10m results -->
### Swift Regex 6.4 (unicodeScalar semantics, simple word boundaries): 10m campaign

* 597,792 patterns, 7 tables, 2,302 distinct findings; self-check 339,984 probes, 1,664 mismatches, 0 engine failures
* findings by kind: 2,282 timeout (batch), 200 selfcheck_mismatch (selfcheck), 20 wrong_result

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 4 | wrong_result | `u` | `"a"` | `" "` | `(?:^\|a){2,}` | 00 |
| 2 | wrong_result | `u` | `"a"` | `" "` | `(?:^\|a){2,}` | 00 |
| 2 | wrong_result | `iu` | `"K"` | `""` | `k+` | 00 |
| 2 | wrong_result | `u` | `"K"` | `"a"` | `(?:[^a\x{E9}]\|^){2,}` | 00 |
| 2 | wrong_result | `iu` | `"K"` | `""` | `K+` | 00 |
| 2 | wrong_result | `iu` | `"K"` | `"a"` | `K*` | 00 |
| 2 | wrong_result | `u` | `"a"` | `""` | `(?:a\|\b^){2,}` | 00 |
| 2 | wrong_result | `u` | `"a"` | `" "` | `(?:a\|^){2,}` | 00 |

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END swift-regex 10m results -->

<!-- BEGIN swift-regex 10m triage -->
### swift-regex: 10-minute campaign triage

* New: **IRX-SWIFT-2** (`k+` with `ignoresCase()` misses Kelvin `K`) and **IRX-SWIFT-3** (`(?:^|a){2,}` misses `"a"`).
* Self-check mismatches: the known IRX-SWIFT-1 `\b` digit rule.
* 2,282 timeouts; only 14,848 cases executed. Timing one batch case by case found 5 cases over 3 s on 8-character
  subjects (nested nullable loops). Swift Regex's backtracker is slow on them, so the target needs smaller
  batches or a longer deadline to be useful.
<!-- END swift-regex 10m triage -->

<!-- BEGIN swift-regex 5m results -->
### Swift Regex 6.4 (unicodeScalar semantics, simple word boundaries): 5m campaign

* 144,544 patterns, 3 tables, 842 distinct findings; self-check 339,984 probes, 1,664 mismatches, 0 engine failures
* findings by kind: 838 timeout (batch), 200 selfcheck_mismatch (selfcheck), 4 wrong_result

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 2 | wrong_result | `iu` | `"Kk"` | `""` | `(?:[k\x{3A3}]\w{0,}){2}\s*(?:)` | 00 |
| 2 | wrong_result | `u` | `"aaa"` | `"a"` | `(?:\B\|a(?:a\|$)){3,}` | 00 |

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END swift-regex 5m results -->
