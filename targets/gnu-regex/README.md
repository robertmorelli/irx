# GNU regex (glibc implementation, via gawk 5.4)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py gnu-regex`.
gawk's bundled copy of the GNU C library's regex (`regcomp`/`regexec`, built by `tools/build_gawk_support.sh`), the closest thing to Linux's grep/sed matcher available on macOS: POSIX ERE, leftmost-longest, C locale (`gnu` dialect). In this build `$[[:space:]]` matches `"\n"` at 0 without `REG_NEWLINE` and `(^a){0,2}` matches `"aa"`; until that is checked against a real glibc, the dialect generates no `^` or `$`. With `REG_ICASE` this copy matches `[a-c]` against `"A"` but not `"a"` (gawk does case-insensitivity its own way), so the target uses no `i` flag sets. Neither behavior has been checked against glibc itself. Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN gnu-regex r10 results -->
### GNU regex (glibc implementation, via gawk 5.4): r10 campaign

* 11,383,456 patterns, 115 tables, 386 distinct findings
* findings by kind: 386 timeout (batch)

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END gnu-regex r10 results -->

<!-- BEGIN gnu-regex r2h results -->
### GNU regex (glibc implementation, via gawk 5.4): r2h campaign

* 75,805,632 patterns, 760 tables, 2,460 distinct findings; self-check 45,772 probes, 0 mismatches, 0 engine failures
* findings by kind: 2,460 timeout (batch)

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END gnu-regex r2h results -->
<!-- BEGIN gnu-regex r2h triage -->
### gnu-regex: r2h (2-hour) campaign triage

* No wrong answers (gawk 5.4.1's GNU regex); self-check clean. All 2,460 findings are batch timeouts under machine load.
<!-- END gnu-regex r2h triage -->
