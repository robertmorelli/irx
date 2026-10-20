# Rust regex

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py rust-regex`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN rust-regex 1m results -->
### rust-regex: 1-minute smoke campaign

* 1,203,072 patterns, 14 tables, 0 distinct findings; self-check 281,792 probes, 216 mismatches, 0 engine failures
* findings by kind: 186 selfcheck_mismatch (selfcheck)

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END rust-regex 1m results -->

<!-- BEGIN rust-regex 30s results -->
### Rust regex: 30s campaign

* 573,216 patterns, 7 tables, 0 distinct findings; self-check 281,792 probes, 216 mismatches, 0 engine failures
* findings by kind: 186 selfcheck_mismatch (selfcheck)

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END rust-regex 30s results -->

<!-- BEGIN rust-regex 10m results -->
### Rust regex: 10m campaign

* 10,844,032 patterns, 110 tables, 0 distinct findings; self-check 339,984 probes, 0 mismatches, 0 engine failures

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END rust-regex 10m results -->

<!-- BEGIN rust-regex 10m triage -->
### rust-regex: 10-minute campaign triage

* Clean: 10.8 M cases, 0 findings, self-check 0 mismatches.
<!-- END rust-regex 10m triage -->

<!-- BEGIN rust-regex 5m results -->
### Rust regex: 5m campaign

* 2,947,104 patterns, 31 tables, 0 distinct findings; self-check 339,984 probes, 0 mismatches, 0 engine failures

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END rust-regex 5m results -->

<!-- BEGIN rust-regex long-10m results -->
### Rust regex: long-10m campaign

* 297,792 patterns, 4 tables, 0 distinct findings; self-check 339,984 probes, 0 mismatches, 0 engine failures

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END rust-regex long-10m results -->

<!-- BEGIN rust-regex rstop results -->
### Rust regex: rstop campaign

* 153,760 patterns, 3 tables, 1,184 distinct findings
* findings by kind: 775 wrong_span, 409 wrong_capture

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 64 | wrong_span | `u` | `"aa"` | `"ϑ"` | `(?:\B\|a)*` | 00 |
| 57 | wrong_span | `u` | `"aa"` | `"aaϑ"` | `(?:\B\|a)*` | 02 |
| 48 | wrong_capture | `u` | `"aa"` | `"aaϑ"` | `(?:\B\|a)*` | 02 |
| 46 | wrong_capture | `u` | `"aa"` | `"ϑ"` | `(?:\B\|a)*` | 00 |
| 28 | wrong_span | `u` | `"aa"` | `"aaϑ"` | `(?:\B\|a)+` | 02 |
| 26 | wrong_capture | `u` | `"aa"` | `"aaϑ"` | `(?:\B\|a)+` | 02 |
| 26 | wrong_span | `u` | `"aa"` | `"ϑ"` | `(?:\B\|a)+` | 00 |
| 24 | wrong_span | `u` | `"aa"` | `"ӏ"` | `(?:\B\|a)*` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END rust-regex rstop results -->

<!-- BEGIN rust-regex rthom results -->
### Rust regex: rthom campaign

* 210,240 patterns, 4 tables, 36 distinct findings
* findings by kind: 24 wrong_span, 12 wrong_capture

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 2 | wrong_span | `u` | `"ϑё"` | `"a"` | `(?:(?:\B\|[^a\x{4CF}]){2})*` | 00 |
| 1 | wrong_capture | `u` | `""` | `".a "` | `(?:.*?)*\b\|()` | 03 |
| 1 | wrong_span | `u` | `""` | `".a "` | `(?:.*?)*\b\|()` | 03 |
| 1 | wrong_span | `u` | `"aa a"` | `""` | `(?x:(?:[^\-\x{4CF}]*?)* \b)` | 00 |
| 1 | wrong_span | `u` | `"a ё"` | `""` | `(?:.*?)*[ \x{451}]` | 00 |
| 1 | wrong_capture | `u` | `"a ё"` | `""` | `(?:.*?)*[ \x{451}]` | 00 |
| 1 | wrong_capture | `u` | `"aKaa"` | `""` | `(?x:a (?:a*? [K\x{DF}]*)*)` | 00 |
| 1 | wrong_span | `u` | `"Ӏaa"` | `""` | `(?:\D*?)*a` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END rust-regex rthom results -->

<!-- BEGIN rust-regex rnfa results -->
### Rust regex: rnfa campaign

* 211,264 patterns, 4 tables, 0 distinct findings

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END rust-regex rnfa results -->

<!-- BEGIN rust-regex rwb results -->
### Rust regex: rwb campaign

* 100,512 patterns, 3 tables, 0 distinct findings

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END rust-regex rwb results -->

<!-- BEGIN rust-regex rglob results -->
### Rust regex: rglob campaign

* 44,544 patterns, 2 tables, 0 distinct findings

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END rust-regex rglob results -->

<!-- BEGIN rust-regex rust5h results -->
### Rust regex: rust5h campaign

* 10,697,792 patterns, 108 tables, 4,517 distinct findings; self-check 14,305,504 probes, 0 mismatches, 109 engine failures
* findings by kind: 4,440 timeout (batch), 61 wrong_span, 16 wrong_capture

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 4 | wrong_span | `iu` | `"Kẞμ IåkA"` | `"ÅKμ  İåkAK"` | `(?:\p{Ll}\|[a-c]\|(?:\z[a~~A]*ı[^\u212B](?:\s$\>\|[^[a-z]--K])\|[^\w~~a])*?)*` | 03 |
| 4 | wrong_span | `su` | `"\na_　᠎b ᠎"` | `"\n　᠎ "` | `(?:(?:(?:[k-s][[a-z]&&A](?:.[^\u{212A}--[a-c]]\A\|[\x{301}]\U0000000B\|\B)[\p{Ll}~~k])*?.)*?)*\S` | 00 |
| 3 | wrong_span | `isu` | `" Kß.Kσİ"` | `" _ß.Kσİß"` | `(?:(?:[^A_]\|(?:\B[^s~~K][^\p{L}[^a]]\p{Po}[k~~A]{3,}?){2})*?)+[\p{L}--k]` | 02 |
| 2 | wrong_span | `iu` | `"😀a््😀́"` | `"😀\ra\r가😀"` | `(?:\A\|(?:\P{dash punctuation}\|\d(?m:(?:[\u{301}\x{AC01}]\|^\x{1F600}[0-9]\|[^[^a]\w]\z).))*?){3,}\w` | 02 |
| 2 | wrong_span | `iu` | `"😀a््😀́"` | `"😀\ra\r가😀"` | `(?:(?:.\|(?:(?:\d[\x{212A}--K](?:\P{General_Category=Other}\|.)\|\d\|$)[^\u{D}\u0915])*?\x{200B})*?)*\P{So}` | 02 |
| 2 | wrong_span | `iu` | `"😀a््😀́"` | `"😀\ra\r가😀"` | `(?:(?:.\|(?:(?:\d[\x{212A}--K](?:\P{General_Category=Other}\|.)\|\d\|$)[^\u{D}\u0915])*?\x{200B})*?)*\P{So}` | 03 |
| 2 | wrong_span | `su` | `"θ_А"` | `"_АΩ_ӏ"` | `(?:(?:[A-Z][\d&&\p{Lu}](?:\u{4CF}\|\w\>)[\U00000391-\x{3A9}]$\|.\|[^\U00000401\U000003C9])*?)*\p{gc!=Ll}` | 00 |
| 2 | wrong_span | `iu` | `".σ_😀S_b😀"` | `".σ_😀_b "` | `(?:(?:[[\u{1F600}a]&&s][[\x{1F600}a]~~[a-z]]\|\S){0,}?)+\B` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END rust-regex rust5h results -->
<!-- BEGIN rust-regex rust5h triage -->
### rust-regex: 5-hour campaign triage

* No regex-crate bugs.
* 4,440 timeouts: batch deadlines missed while other programs held the CPU (load 27–47 on 8 cores); the batches replay in under 3 s.
* 77 span/capture findings (22 patterns): a model gap, fixed. Every one has an empty class (`[a&&\W]`, `[^[^a]\p{L}]`). regex-syntax gives it no minimum length, which poisons the enclosing alternation, concatenation and repetition, so regex-automata compiles the loop around it as `(e+)?`. An alternation is merged into one class first only when every flattened branch is a class. With the fix the model agrees with the crate on all 22.
<!-- END rust-regex rust5h triage -->

<!-- BEGIN rust-regex r10 results -->
### Rust regex: r10 campaign

* 872,192 patterns, 10 tables, 0 distinct findings

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END rust-regex r10 results -->

<!-- BEGIN rust-regex r2h results -->
### Rust regex: r2h campaign

* 211,264 patterns, 4 tables, 0 distinct findings; self-check 14,319,840 probes, 0 mismatches, 81 engine failures

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END rust-regex r2h results -->
<!-- BEGIN rust-regex r2h triage -->
### rust-regex: r2h (2-hour) campaign triage

Rust `regex` crate.

* No findings. Run cut short: from 11:04 a lane was stuck in the model's `classEmpty` Unicode scan again (the per-tree memo missed); fixed in irx with a per-thread cache keyed by the atom and its flags, and stopped with SIGINT at 11:28.
<!-- END rust-regex r2h triage -->
