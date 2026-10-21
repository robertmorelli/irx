# Swift Regex 6.4 (unicodeScalar semantics, simple word boundaries)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py swift-regex`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN swift-regex 1m results -->
### swift-regex: 1-minute smoke campaign

* 57,344 patterns, 2 tables, 224 distinct findings; self-check 339,984 probes, 1,664 mismatches, 0 engine failures
* findings by kind: 224 timeout (batch), 200 selfcheck_mismatch (selfcheck)

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
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

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
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

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END swift-regex 5m results -->

<!-- BEGIN swift-regex long-10m results -->
### Swift Regex 6.4 (unicodeScalar semantics, simple word boundaries): long-10m campaign

* 17,408 patterns, 2 tables, 102 distinct findings; self-check 339,984 probes, 1,664 mismatches, 0 engine failures
* findings by kind: 102 timeout (batch), 80 selfcheck_mismatch (selfcheck)

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END swift-regex long-10m results -->

<!-- BEGIN swift-regex r10 results -->
### Swift Regex 6.4 (unicodeScalar semantics, simple word boundaries): r10 campaign

* 4,565,536 patterns, 47 tables, 8,018 distinct findings
* findings by kind: 4,000 wrong_result, 2,000 wrong_capture, 2,000 wrong_span, 18 timeout (batch)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 113 | wrong_result | `iu` | `""` | `"à"` | `[\x{C0}-\x{DE}]*` | 03 |
| 113 | wrong_result | `iu` | `""` | `"à"` | `[\x{C0}-\x{DE}]*` | 33 |
| 55 | wrong_span | `iu` | `"a"` | `"à"` | `[\x{C0}-\x{DE}]\|a` | 03 |
| 55 | wrong_capture | `iu` | `"a"` | `"à"` | `[\x{C0}-\x{DE}]\|a` | 03 |
| 55 | wrong_result | `iu` | `"ΐ"` | `""` | `[^\x{410}\x{1FD3}]` | 00 |
| 52 | wrong_result | `iu` | `"ΐ"` | `""` | `[^a\x{1FD3}]` | 00 |
| 49 | wrong_capture | `iu` | `""` | `"à"` | `[\x{C0}-\x{DE}]*` | 03 |
| 49 | wrong_span | `iu` | `""` | `"à"` | `[\x{C0}-\x{DE}]*` | 03 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END swift-regex r10 results -->

<!-- BEGIN swift-regex r10b results -->
### Swift Regex 6.4 (unicodeScalar semantics, simple word boundaries): r10b campaign

* 4,027,648 patterns, 42 tables, 8,020 distinct findings
* findings by kind: 4,000 wrong_result, 2,000 wrong_span, 2,000 wrong_capture, 20 timeout (batch)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 468 | wrong_span | `u` | `"a"` | `"_ "` | `\w` | 03 |
| 467 | wrong_capture | `u` | `"a"` | `"_ "` | `\w` | 03 |
| 287 | wrong_span | `u` | `""` | `"_ "` | `\w*` | 03 |
| 287 | wrong_capture | `u` | `""` | `"_ "` | `\w*` | 03 |
| 148 | wrong_result | `u` | `"aaaaaa0θ"` | `"aaaaaaa"` | `(?:\w.)*` | 00 |
| 108 | wrong_capture | `u` | `""` | `"_ "` | `\w\|` | 03 |
| 106 | wrong_span | `u` | `""` | `"_ "` | `\w\|` | 03 |
| 104 | wrong_span | `u` | `""` | `"_ "` | `\w\|()` | 03 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END swift-regex r10b results -->

<!-- BEGIN swift-regex r2h results -->
### Swift Regex 6.4 (unicodeScalar semantics, simple word boundaries): r2h campaign

* 61,925,600 patterns, 621 tables, 8,481 distinct findings; self-check 5,101,568 probes, 8,416 mismatches, 0 engine failures
* findings by kind: 4,000 wrong_result, 2,000 wrong_capture, 2,000 wrong_span, 481 timeout (batch), 80 selfcheck_mismatch (selfcheck)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 468 | wrong_span | `u` | `"a"` | `"_ "` | `\w` | 03 |
| 467 | wrong_capture | `u` | `"a"` | `"_ "` | `\w` | 03 |
| 287 | wrong_capture | `u` | `""` | `"_ "` | `\w*` | 03 |
| 287 | wrong_span | `u` | `""` | `"_ "` | `\w*` | 03 |
| 162 | wrong_result | `u` | `"aaaaaa0θ"` | `"aaaaaaa"` | `(?:\w.)*` | 00 |
| 108 | wrong_capture | `u` | `""` | `"_ "` | `\w\|` | 03 |
| 106 | wrong_span | `u` | `""` | `"_ "` | `\w\|` | 03 |
| 106 | wrong_result | `u` | `"aaaaaa0θ"` | `"aaaaaaa"` | `(?:\w.)+` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END swift-regex r2h results -->
<!-- BEGIN swift-regex r2h triage -->
### swift-regex: r2h (2-hour) campaign triage

Swift Regex (Swift 6.4), `.unicodeScalar` semantics.

* New: IRX-SWIFT-8 (backreferences ignore case-insensitive matching: `(?i)(a)\1` misses `"aA"`).
* Known: IRX-SWIFT-6 (`\w` misses `_` or a digit before a scalar at U+0300 or above, e.g. U+2028), most wrong answers; IRX-SWIFT-5 (a greedy loop before an alternation does not backtrack: `a+(?:-|a)` misses `"aa"`); IRX-SWIFT-1 (`\b`/`\B`), all 8,416 self-check mismatches.
<!-- END swift-regex r2h triage -->
