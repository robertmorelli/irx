# Emacs Lisp regexps (translated)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py emacs`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN emacs 1m results -->
### emacs: 1-minute smoke campaign

* 295,232 patterns, 4 tables, 32,261 distinct findings; self-check 281,792 probes, 31,804 mismatches, 0 engine failures
* findings by kind: 32,203 wrong_result, 198 selfcheck_mismatch (selfcheck), 58 timeout (batch)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 4 | wrong_result | `u` | `"aaaa"` | `"a"` | `(?:aa{1,1}?)+` | 03 |
| 3 | wrong_result | `u` | `"aaa_aaaa"` | `"a"` | `(?:a\B.)*` | 00 |
| 3 | wrong_result | `u` | `"aaaa"` | `"aa"` | `(?:a{2,}?){2,2}` | 03 |
| 2 | wrong_result | `u` | `"aaaaΣaaa"` | `"a"` | `(?:\w\Ba)*` | 00 |
| 2 | wrong_result | `u` | `"aaa_aaaa"` | `"a"` | `(?:a\w){0,}` | 00 |
| 2 | wrong_result | `u` | `"aaaa"` | `"a"` | `(?:a{1,1}?a)*` | 03 |
| 2 | wrong_result | `u` | `"aaaa"` | `"a"` | `(?:a{1,1}?a)+` | 03 |
| 2 | wrong_result | `u` | `"Σa"` | `""` | `.\Ba` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END emacs 1m results -->

<!-- BEGIN emacs 10m results -->
### Emacs Lisp regexps (translated): 10m campaign

* 1,975,264 patterns, 21 tables, 1,510 distinct findings; self-check 339,984 probes, 0 mismatches, 0 engine failures
* findings by kind: 1,502 timeout (batch), 8 crash (batch)

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END emacs 10m results -->

<!-- BEGIN emacs 10m triage -->
### emacs: 10-minute campaign triage

* New: **IRX-EMACS-1**, the 8 crashes: SIGABRT in `forall_firstchar_1` during `regex_compile`. It only reproduces
  with a whole recorded batch (minimized to 10 patterns, `docs/repros/IRX-EMACS-1.jsonl`).
* No wrong results; self-check clean after the dialect work.
* 1,502 timeouts, none reproduced alone; Emacs's backtracker is slow on the longer subjects. Not investigated further.
<!-- END emacs 10m triage -->

<!-- BEGIN emacs 5m results -->
### Emacs Lisp regexps (translated): 5m campaign

* 659,904 patterns, 8 tables, 427 distinct findings; self-check 339,984 probes, 0 mismatches, 0 engine failures
* findings by kind: 425 timeout (batch), 2 crash (batch)

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END emacs 5m results -->

<!-- BEGIN emacs 30m results -->
### Emacs Lisp regexps (translated): 30m campaign

* 4,078,848 patterns, 42 tables, 2,266 distinct findings; self-check 339,984 probes, 0 mismatches, 0 engine failures
* findings by kind: 2,117 timeout (batch), 61 wrong_span, 57 wrong_capture, 31 crash (batch)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 3 | wrong_capture | `su` | `"\naaa"` | `"aaaa"` | `(?:(?:.\|()){0,3}\b)+` | 00 |
| 3 | wrong_span | `su` | `"\naaa"` | `"aaaa"` | `(?:(?:.\|()){0,3}\b)+` | 00 |
| 2 | wrong_span | `su` | `"\naaa"` | `"aaaa"` | `(?:(?:.\|){0,3}\b)*` | 00 |
| 2 | wrong_capture | `su` | `"\naaa"` | `"aaaa"` | `(?:(?:.\|()){0,3}\b)*` | 00 |
| 2 | wrong_span | `su` | `"\naaa"` | `"aaaa"` | `(?:(?:.?){0,3}\b){0,}` | 00 |
| 2 | wrong_span | `su` | `"\naaa"` | `"aaaa"` | `(?:(?:.?){0,3}\b)*` | 00 |
| 2 | wrong_capture | `su` | `"\naaa"` | `"aaaa"` | `(?:(?:.?){0,3}\b){0,}` | 00 |
| 2 | wrong_span | `u` | `"a"` | `"a "` | `(?:^(?:a\|)*){2,2}` | 02 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END emacs 30m results -->

<!-- BEGIN emacs long-10m results -->
### Emacs Lisp regexps (translated): long-10m campaign

* 117,408 patterns, 3 tables, 17 distinct findings; self-check 339,984 probes, 0 mismatches, 0 engine failures
* findings by kind: 15 timeout (batch), 1 wrong_capture, 1 wrong_span

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 1 | wrong_capture | `u` | `"- kß "` | `"-K0ß"` | `(?:^(?:\D\|){0,}){2,}` | 02 |
| 1 | wrong_span | `u` | `"- kß "` | `"-K0ß"` | `(?:^(?:\D\|){0,}){2,}` | 02 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END emacs long-10m results -->

<!-- BEGIN emacs r10 results -->
### Emacs Lisp regexps (translated): r10 campaign

* 1,719,456 patterns, 19 tables, 606 distinct findings
* findings by kind: 564 timeout (batch), 20 wrong_span, 18 wrong_capture, 4 crash (batch)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 2 | wrong_capture | `u` | `"a"` | `"aS"` | `(?:^(?:a*)*){2,2}` | 02 |
| 2 | wrong_span | `u` | `"a"` | `"aS"` | `(?:^(?:a*)*){2,2}` | 02 |
| 1 | wrong_capture | `u` | `"a"` | `"a_"` | `(?:^(?:a?)*){2,}` | 02 |
| 1 | wrong_span | `u` | `"K"` | `"Ka"` | `(?:^(?:[K\x{2028}]\|)*){2,2}` | 02 |
| 1 | wrong_span | `u` | `"a_"` | `"a_a"` | `(?:(?:a\|)*(?:\W\|^)){2,2}` | 02 |
| 1 | wrong_capture | `u` | `"a_"` | `"a_a"` | `(?:(?:a\|)*(?:\W\|^)){2,2}` | 02 |
| 1 | wrong_capture | `u` | `"K"` | `"Ka"` | `(?:^(?:[K\x{2028}]\|)*){2,2}` | 02 |
| 1 | wrong_span | `u` | `"a"` | `"a_"` | `(?:^(?:a?)*){2,}` | 02 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END emacs r10 results -->

<!-- BEGIN emacs r2h results -->
### Emacs Lisp regexps (translated): r2h campaign

* 18,988,576 patterns, 191 tables, 13,095 distinct findings; self-check 1,856,592 probes, 640 mismatches, 0 engine failures
* findings by kind: 4,955 timeout (batch), 4,000 wrong_result, 2,000 wrong_span, 2,000 wrong_capture, 140 crash (batch), 40 selfcheck_mismatch (selfcheck)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 72 | wrong_span | `u` | `"a"` | `"️́"` | `.\b` | 03 |
| 70 | wrong_capture | `u` | `"a"` | `"️́"` | `.\b` | 03 |
| 64 | wrong_span | `u` | `""` | `"️́"` | `(?:\b.)*` | 03 |
| 57 | wrong_capture | `u` | `""` | `"️́"` | `(?:\b.)*` | 03 |
| 33 | wrong_span | `u` | `"a"` | `"️́"` | `(?:\b.)+` | 03 |
| 31 | wrong_capture | `u` | `"a"` | `"️́"` | `(?:\b.)+` | 03 |
| 31 | wrong_span | `u` | `""` | `"️́"` | `(?:.\b)*` | 03 |
| 29 | wrong_capture | `u` | `""` | `"️́"` | `(?:.\b)*` | 03 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END emacs r2h results -->
<!-- BEGIN emacs r2h triage -->
### emacs: r2h (2-hour) campaign triage

* No new bugs. IRX-EMACS-1 (SIGABRT in `regex_compile`): the 140 crashes. IRX-EMACS-2 (`(?:^(?:a*)*){2,2}` spans): about 200.
* Model gap, fixed: `\b` between two word characters now follows `word_boundary_p` (category.c) and `WORD_BOUNDARY_P`: never between two characters below U+0100 (`a` before U+0085), and a `word-combining-categories` entry such as `(nil . ^)` applies only when exactly one side has the category, so two combining marks of different scripts (U+FE0F U+0301) are a boundary. The table generator now dumps Emacs's `^`, `C`, `H`, `K` category sets. About 7,800 findings and all 640 self-check mismatches; a rerun of the self-check is clean.
* 4,955 timeouts: Emacs is slow on large batches under load.
<!-- END emacs r2h triage -->
