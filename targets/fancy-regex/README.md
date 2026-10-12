# fancy-regex

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py fancy-regex`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN fancy-regex 1m results -->
### fancy-regex: 1-minute smoke campaign

* 385,504 patterns, 5 tables, 44,720 distinct findings; self-check 281,792 probes, 216 mismatches, 0 engine failures
* findings by kind: 44,708 syntax_error, 186 selfcheck_mismatch (selfcheck), 12 exception

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 403 | syntax_error | `u` | `""` | `"a"` | `(?:)*` | 04 |
| 295 | syntax_error | `u` | `""` | `"a"` | `(?:){0,1}` | 04 |
| 270 | syntax_error | `u` | `"a"` | `""` | `(?:)?a` | 04 |
| 252 | syntax_error | `u` | `""` | `"a"` | `(?:)?` | 04 |
| 219 | syntax_error | `u` | `"a"` | `""` | `a(?:)?` | 04 |
| 178 | syntax_error | `u` | `"a"` | `""` | `a(?:){0,1}` | 04 |
| 173 | syntax_error | `u` | `""` | `"a"` | `(?:)+` | 04 |
| 158 | syntax_error | `u` | `"a"` | `""` | `(?:){0,1}a` | 04 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END fancy-regex 1m results -->

<!-- BEGIN fancy-regex 10m results -->
### fancy-regex: 10m campaign

* 4,577,312 patterns, 47 tables, 6,835 distinct findings; self-check 339,984 probes, 0 mismatches, 0 engine failures
* findings by kind: 6,834 exception, 1 timeout (batch)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 2 | exception | `u` | `"a"` | `"aaaaaaaaa-éK\nAσKσKΣk "` | `a(?=(?:\b\|[^A0]\|.)*)` | 08 |
| 2 | exception | `u` | `""` | `"aaaaaéK\nAσKσKΣk "` | `(?:(?:(?:(?:(?!(?:))\|a\|a)*)?)+)+` | 08 |
| 2 | exception | `u` | `""` | `"aaaaaaaaaaaaaaaaaAσKσKΣk "` | `(?:(?:a\|(?:)\|(?!(?:))){0,2}){0,}` | 08 |
| 2 | exception | `u` | `"a"` | `"aaaaaAσKσKΣk "` | `(?:a(?=(?:(?:\B\|a){0,2})*))+` | 08 |
| 2 | exception | `u` | `""` | `"aaaaaaa\nAσKσKΣk "` | `(?:(?:\B\|a\|(?:)){0,2})+` | 08 |
| 2 | exception | `su` | `""` | `"aaaaaaaaK\nAσKσKΣk "` | `(?:(?:\B\|.)*){0,}a\|(?:)` | 08 |
| 2 | exception | `u` | `""` | `"a.a😀ſ-😀Kı-éK\nAσKσKΣk "` | `(?:(?:\S\|\b){0,2})*` | 08 |
| 2 | exception | `u` | `""` | `"a.a😀a😀aı-éK\nAσKσKΣk "` | `(?:(?:\b\|\S){0,2})*` | 08 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END fancy-regex 10m results -->

<!-- BEGIN fancy-regex 10m triage -->
### fancy-regex: 10-minute campaign triage

* No wrong results; self-check clean; 4.6 M cases.
* All 6,834 exceptions are `is_match` returning `Err` on long subjects with nested nullable or overlapping
  alternatives (`a(?=(?:\b|[^A0]|.)*)` on a 20-char subject): exponential backtracking hitting fancy-regex's
  backtrack limit (1,000,000 steps by default), a documented resource limit rather than a bug.
<!-- END fancy-regex 10m triage -->

<!-- BEGIN fancy-regex 5m results -->
### fancy-regex: 5m campaign

* 1,621,504 patterns, 18 tables, 3,005 distinct findings; self-check 339,984 probes, 0 mismatches, 0 engine failures
* findings by kind: 3,005 exception

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 3 | exception | `iu` | `"kΣ"` | `"aaa"` | `(?:(?:\b\|(?:a\|){0,3})+){0,3}[K\x{212A}][^a\x{E9}]` | 08 |
| 3 | exception | `u` | `"aaaaaa"` | `""` | `(?:(?:(?:a\b){0,}(?:(?:a*){3,})*a){3,}){2}` | 08 |
| 3 | exception | `su` | `" a\nß-S"` | `""` | `(?:\s(?:(?:[^a ]\|(?:(?:)\|\b\|.){0,1})+)*.){2,2}` | 08 |
| 3 | exception | `su` | `" \naa"` | `""` | `(?:\s(?:(?:(?:(?:.\|\B)*){0,3}){1,})+){2,}` | 08 |
| 3 | exception | `u` | `"ka"` | `"aaa"` | `(?:(?:(?:a*){0,2}a?)+\|(?=(?:)))+[k-s]a` | 08 |
| 3 | exception | `u` | `" a\naaaa"` | `""` | `(?:\s(?:(?:(?:a\|\D)*)+\|(?<!()))+a){2}` | 08 |
| 3 | exception | `u` | `" a\na-a"` | `""` | `(?:\W(?:(?:.*\|\|\b){0,3})+a){3}` | 08 |
| 3 | exception | `u` | `"aaaaaaaa"` | `"aaaaa"` | `(?:(?:a(?:(?:\|a){0,2}\|\B){0,3}a){2,}){2,2}` | 08 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END fancy-regex 5m results -->

<!-- BEGIN fancy-regex 30m results -->
### fancy-regex: 30m campaign

* 8,674,752 patterns, 88 tables, 6,019 distinct findings; self-check 339,984 probes, 0 mismatches, 0 engine failures
* findings by kind: 5,900 exception, 119 wrong_capture

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 4 | exception | `u` | `"aaaa"` | `"aa"` | `(?:(?:a(?:(?:()\|(?:\ba)*){0,3}){0,3}){2,2}){2}` | 08 |
| 4 | exception | `u` | `"aaaaaaa"` | `" "` | `(?:(?=(?:(?:(?:(?:)\|(?<!(?:))\|a*)+){0,2}){0,2})\|a)*` | 08 |
| 4 | exception | `u` | `"-\n"` | `"-aaa"` | `(?:\W(?:(?:a?\|\b\|(?:)\|a*)+){2,}){2,2}` | 08 |
| 4 | exception | `u` | `"aaaaaa"` | `""` | `(?:(?:(?:(?:a{0,1}){0,3}\|(?!()))+a){3,3}){2,2}` | 08 |
| 4 | exception | `u` | `" "` | `""` | `(?:(?:(?:()\|\|a){0,2}){0,3}){0,3}.\B` | 08 |
| 4 | exception | `u` | `""` | `"Σ"` | `(?:(?:(?:(?:(?:(?:)\|[^_\x{E9}]){0,2}){0,3}){0,2})*a\b)*` | 08 |
| 4 | exception | `u` | `" -\n"` | `""` | `(?:\W(?:(?:(?:(?:)\|(?:)\|[^\x{E0}])(?:(?:)\|\B)){0,3})*){3,}` | 08 |
| 4 | exception | `u` | `"aaaaaa"` | `""` | `(?:(?:a(?:(?:(?:a\|\B){0,2})+){0,}){3}){2,2}` | 08 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END fancy-regex 30m results -->

<!-- BEGIN fancy-regex long-10m results -->
### fancy-regex: long-10m campaign

* 273,216 patterns, 4 tables, 1 distinct findings; self-check 339,984 probes, 0 mismatches, 0 engine failures
* findings by kind: 1 wrong_capture

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 1 | wrong_capture | `u` | `"ba"` | `".a "` | `(?:(?:^(?<g1>[a-c])\|\D)\Ba)*` | 02 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END fancy-regex long-10m results -->
