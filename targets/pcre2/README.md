# PCRE2 10.49 (interpreter; IRX_PCRE2_JIT=1 for the JIT)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py pcre2`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN pcre2 1m results -->
### pcre2: 1-minute smoke campaign

* 447,104 patterns, 6 tables, 204 distinct findings; self-check 281,792 probes, 0 mismatches, 0 engine failures
* findings by kind: 162 timeout (batch), 42 exception

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 2 | exception | `u` | `"a\r"` | `"aaà\r"` | `(?:(?:(?:\D?){0,}){0,3})*a\x{D}` | 08 |
| 2 | exception | `u` | `"aaaaaaaa"` | `""` | `(?:(?:(?:(?:a(?:(?:)\|(?:)\|(?:){0,1}))+){2,}){2,2}){2}` | 08 |
| 2 | exception | `u` | `"aa"` | `"aaàa"` | `(?:(?:(?:(?:(?:)\|.)*)+\|(?:))*)+aa` | 08 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END pcre2 1m results -->

<!-- BEGIN pcre2 10m results -->
### PCRE2 10.49 (interpreter; IRX_PCRE2_JIT=1 for the JIT): 10m campaign

* 3,571,168 patterns, 37 tables, 2,619 distinct findings; self-check 281,792 probes, 0 mismatches, 0 engine failures
* findings by kind: 1,470 exception, 1,149 timeout (batch)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 2 | exception | `u` | `""` | `"aaaaaaaaaaaa.àA AςſςſΣk "` | `(?:(?:(?:)\|a){0,2})*` | 08 |
| 2 | exception | `u` | `"a"` | `"aaaaaaaaaaaaaaaaaaaaaa "` | `(?:a(?:)?)+` | 08 |
| 2 | exception | `u` | `"a\r"` | `"aaà\r"` | `(?:(?:(?:\D?){0,}){0,3})*a\x{D}` | 08 |
| 2 | exception | `u` | `"aaaaaaaa"` | `""` | `(?:(?:(?:(?:a(?:(?:)\|(?:)\|(?:){0,1}))+){2,}){2,2}){2}` | 08 |
| 2 | exception | `u` | `"aa"` | `"aaàa"` | `(?:(?:(?:(?:(?:)\|.)*)+\|(?:))*)+aa` | 08 |
| 2 | exception | `u` | `""` | `"aaaaaaaaaaaaaaaaaaaaaa "` | `(?:a(?:)?)*` | 08 |
| 2 | exception | `u` | `"aaaaé-K"` | `""` | `(?:a(?:(?:(?:.\|(?:)){3,})*){0,}){3,3}` | 08 |
| 2 | exception | `u` | `"aaaaaaaa"` | `""` | `(?:(?:(?:a(?:(?:(?:)\|(?:)\|(?:))*\|(?:)?))+){3}a){2,2}` | 08 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END pcre2 10m results -->

<!-- BEGIN pcre2 10m triage -->
### pcre2: 10-minute campaign triage

* No wrong results; self-check clean; 3.6 M cases.
* The 1,470 exceptions are PCRE2's match limit on exponential nested nullable loops (`(?:a(?:)?)+` over 23
  characters), a resource limit. 1,149 timeouts are the same blowups under the batch deadline.
* IRX-PCRE2-1 (JIT negative lookbehind) did not come up in this run.
<!-- END pcre2 10m triage -->

<!-- BEGIN pcre2 5m results -->
### PCRE2 10.49 (interpreter; IRX_PCRE2_JIT=1 for the JIT): 5m campaign

* 992,160 patterns, 11 tables, 890 distinct findings; self-check 281,792 probes, 0 mismatches, 0 engine failures
* findings by kind: 572 exception, 317 timeout (batch), 1 wrong_span

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 3 | exception | `u` | `"\r"` | `"aaa"` | `(?:(?:(?:()\|){0,2}){0,2}a){0,}[^a\x{1F600}]` | 08 |
| 3 | exception | `u` | `"aaaaaaaa"` | `""` | `(?:(?:(?:(?:a\|)+)+)+a{2,}aa){2,2}` | 08 |
| 3 | exception | `u` | `"aak\r"` | `"aàa"` | `(?:(?:(?:(?:)*){0,3}){0,2}){0,3}aa[k-s]\W` | 08 |
| 3 | exception | `u` | `"aaaaaaaa"` | `"Kaaaaa"` | `(?:.(?:a(?:(?:()\|)*){0,3}){3,}){2,2}` | 08 |
| 3 | exception | `u` | `"aaa"` | `"a\naa"` | `(?:(?:(?:(?:()\|[^\x{1F600}\x{E9}])*)*){0,3}){0,2}aaa` | 08 |
| 2 | exception | `u` | `""` | `"aaaſ"` | `(?:(?:(?:()\|(?:)){3,}(?:a\|(?:))){2,}){0,2}` | 08 |
| 2 | exception | `u` | `"aaaaaa"` | `"aaaaa"` | `(?:(?:a(?:\|()\|()){0,3}){2,3}a)+` | 08 |
| 2 | exception | `u` | `""` | `"aaſ"` | `(?:(?:(?:(?:a?){0,1}){2,}){0,3})+` | 08 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END pcre2 5m results -->

<!-- BEGIN pcre2 30m results -->
### PCRE2 10.49 (interpreter; IRX_PCRE2_JIT=1 for the JIT): 30m campaign

* 13,380,896 patterns, 135 tables, 9,275 distinct findings; self-check 281,792 probes, 0 mismatches, 0 engine failures
* findings by kind: 9,093 exception, 95 timeout (batch), 44 wrong_capture, 43 wrong_span

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 4 | exception | `u` | `"aaaaaa"` | `""` | `(?:(?:(?:(?:(?:a*){0,}){0,})+a){3}){2}` | 08 |
| 4 | exception | `u` | `"aaaaaa"` | `""` | `(?:(?:a(?:(?:(?:)\|())()?){0,3}){2,}){3,3}` | 08 |
| 4 | exception | `u` | `"aa.aaaa"` | `""` | `(?:(?:(?:.*){0,3})*a{1,}a){3,}` | 08 |
| 4 | exception | `u` | `". "` | `"-aaa"` | `(?:\W(?:(?:(?:a{0,1})*\|()){0,3})*){2,}` | 08 |
| 4 | exception | `u` | `"aaaaaa"` | `""` | `(?:a(?:a(?:(?:(?:)?\|())*){0,3})+){3}` | 08 |
| 4 | exception | `u` | `"aaaaaa"` | `""` | `(?:(?:(?:(?:(?:)\|()){0,3}\|())a){2,}){3,}` | 08 |
| 4 | exception | `u` | `"aaaaaa"` | `""` | `(?:a(?:(?:(?:a\|)?){0,3})+a){3,3}` | 08 |
| 4 | exception | `u` | `"aaaaaa"` | `""` | `(?:(?:(?:\|(?:){0,1}){0,3}){0,2}(?:\d\|a+)a){3}` | 08 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END pcre2 30m results -->
