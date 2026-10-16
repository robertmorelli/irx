# macOS libc regex (regcomp/regexec)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py libc-regex`.
The C library's POSIX ERE matcher (on macOS the TRE-based libc regex), in the C locale so it matches bytes,
with leftmost-longest spans. It shares the Perl-to-ERE translation of [`llvm-regex`](../llvm-regex) (a separate,
Spencer-derived implementation) and the same model (`libc` dialect). Bugs found here are listed in the
[bug ledger](../../README.md#bug-ledger).

<!-- BEGIN libc-regex r10 results -->
### macOS libc regex (regcomp/regexec): r10 campaign

* 15,333,792 patterns, 155 tables, 2,002 distinct findings
* findings by kind: 2,000 wrong_span, 2 crash (batch)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 85 | wrong_span | `u` | `"aaaaaaaa"` | `"aaaaa"` | `(?:(?:aa)+){1,2}` | 03 |
| 82 | wrong_span | `u` | `"aaaaaaaa"` | `"aaaaa"` | `(?:a(?:a\|(?:)a))+` | 03 |
| 59 | wrong_span | `u` | `"aaaaaaaa"` | `"aaaaa"` | `(?:(?:aa){1,2})+` | 03 |
| 55 | wrong_span | `u` | `"aaaaaaaa"` | `"aaaaa"` | `(?:a(?:a\|()a))+` | 03 |
| 47 | wrong_span | `u` | `"aaaaaaaa"` | `"aaaaa"` | `(?:a(?:(?:)a\|a))+` | 03 |
| 40 | wrong_span | `u` | `"aaaaaaaa"` | `"aaaaaaa"` | `(?:a(?:(?:)a\|a))+` | 03 |
| 29 | wrong_span | `u` | `"aaaaaaaa"` | `"aaaaa"` | `(?:a(?:a\|a(?:)))+` | 03 |
| 24 | wrong_span | `u` | `"aaaaaaaa"` | `"aaaaa"` | `(?:a(?:a(?:)\|a))+` | 03 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END libc-regex r10 results -->

<!-- BEGIN libc-regex r2h results -->
### macOS libc regex (regcomp/regexec): r2h campaign

* 181,388,064 patterns, 1815 tables, 2,000 distinct findings; self-check 91,544 probes, 0 mismatches, 0 engine failures
* findings by kind: 2,000 wrong_span

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 84 | wrong_span | `u` | `"aaaaaaaa"` | `"aaaaa"` | `(?:(?:aa)+){1,2}` | 03 |
| 82 | wrong_span | `u` | `"aaaaaaaa"` | `"aaaaa"` | `(?:a(?:a\|(?:)a))+` | 03 |
| 59 | wrong_span | `u` | `"aaaaaaaa"` | `"aaaaa"` | `(?:(?:aa){1,2})+` | 03 |
| 55 | wrong_span | `u` | `"aaaaaaaa"` | `"aaaaa"` | `(?:a(?:a\|()a))+` | 03 |
| 47 | wrong_span | `u` | `"aaaaaaaa"` | `"aaaaa"` | `(?:a(?:(?:)a\|a))+` | 03 |
| 40 | wrong_span | `u` | `"aaaaaaaa"` | `"aaaaaaa"` | `(?:a(?:(?:)a\|a))+` | 03 |
| 29 | wrong_span | `u` | `"aaaaaaaa"` | `"aaaaa"` | `(?:a(?:a\|a(?:)))+` | 03 |
| 24 | wrong_span | `u` | `"aaaaaaaa"` | `"aaaaa"` | `(?:a(?:a(?:)\|a))+` | 03 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END libc-regex r2h results -->
<!-- BEGIN libc-regex r2h triage -->
### libc-regex: r2h (2-hour) campaign triage

macOS 27.0.1 libc (`regcomp`/`regexec`, TRE).

* No new bugs. All 2,000 findings are IRX-LIBC-2 (not leftmost: `(?:(?:aa)+){1,2}` on `"aaaaaaa"` → `[1,7)`, expected `[0,6)`). Self-check clean; about 181 million patterns.
<!-- END libc-regex r2h triage -->
