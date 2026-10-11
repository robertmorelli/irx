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

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END emacs 1m results -->

<!-- BEGIN emacs 10m results -->
### Emacs Lisp regexps (translated): 10m campaign

* 1,975,264 patterns, 21 tables, 1,510 distinct findings; self-check 339,984 probes, 0 mismatches, 0 engine failures
* findings by kind: 1,502 timeout (batch), 8 crash (batch)

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
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

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END emacs 5m results -->
