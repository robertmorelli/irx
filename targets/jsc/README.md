# JavaScriptCore (macOS system jsc)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py jsc`.
The `jsc` shell inside macOS's JavaScriptCore framework, running `driver.js` directly (YARR, the same engine family as [`bun`](../bun) but the system build and the plain shell, without Bun's runtime). Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN jsc r10 results -->
### JavaScriptCore (macOS system jsc): r10 campaign

* 282,944 patterns, 4 tables, 8,032 distinct findings
* findings by kind: 3,875 wrong_span, 2,698 wrong_result, 1,321 wrong_capture, 138 timeout (batch)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 32 | wrong_result | `iu` | `"Ӏa"` | `""` | `\P{Lu}a` | 00 |
| 27 | wrong_span | `iu` | `"Ӏa"` | `""` | `\P{Lu}a` | 00 |
| 24 | wrong_result | `iu` | `"Ӏ"` | `""` | `\P{Lu}` | 00 |
| 22 | wrong_result | `iu` | `"aa"` | `""` | `a\P{Ll}` | 00 |
| 19 | wrong_span | `u` | `"a"` | `"aa"` | `(?i:\p{Lu})` | 02 |
| 18 | wrong_span | `iu` | `"Ӏ"` | `""` | `\P{Lu}` | 00 |
| 18 | wrong_span | `iu` | `"Ӏ"` | `"aa"` | `\P{Lu}` | 00 |
| 18 | wrong_result | `iu` | `"Ӏ"` | `"aa"` | `\P{Lu}` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END jsc r10 results -->

<!-- BEGIN jsc r2h results -->
### JavaScriptCore (macOS system jsc): r2h campaign

* 7,251,712 patterns, 74 tables, 18,381 distinct findings; self-check 21,012,224 probes, 133,328 mismatches, 0 engine failures
* findings by kind: 8,000 wrong_span, 4,381 timeout (batch), 4,000 wrong_result, 2,000 wrong_capture, 20 selfcheck_mismatch (selfcheck)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 440 | wrong_result | `iu` | `"aa"` | `""` | `a\P{Ll}` | 00 |
| 273 | wrong_result | `iu` | `"aA"` | `""` | `a\P{Lu}` | 00 |
| 272 | wrong_result | `iu` | `"a"` | `"aa"` | `\P{Ll}` | 00 |
| 269 | wrong_span | `iu` | `"aA"` | `""` | `a\P{Lu}` | 00 |
| 216 | wrong_result | `iu` | `"Ӏa"` | `""` | `\P{Lu}a` | 00 |
| 214 | wrong_span | `iu` | `"Ӏa"` | `""` | `\P{Lu}a` | 00 |
| 210 | wrong_span | `iu` | `"aa"` | `"aaa"` | `a\P{Ll}` | 02 |
| 200 | wrong_span | `iu` | `"aa"` | `""` | `a\P{Ll}` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END jsc r2h results -->
<!-- BEGIN jsc r2h triage -->
### jsc: r2h (2-hour) campaign triage

macOS 27.0.1 JavaScriptCore 22625.1.29.11.28 (Bun 1.4.2's newer JavaScriptCore is correct on every shape below).

* New: IRX-JSC-5 (a quantified `^` in a later alternative breaks alternation priority after index 0: `/aa|a|(?:^){1,2}a/.exec(".aa")` → `[1,2)`).
* Widened: IRX-JSC-4 also fails without the outer complement (`/^[[^a]A]$/v.test("a")` → `true`).
* Known: IRX-JSC-3 (case-insensitive `\p{Lu}`/`\p{Ll}`, also as `(?i:\p{Lu})`), about 7,000 findings and most self-check mismatches; IRX-V8-3's surrogate-pair bug (the driver's multiline full-match wrapper `(?<![\s\S])(?:$[^]*)(?![\s\S])` matches inside `"a😀"`), the `$[^]*`/`[^]{1}$[^]*` self-check mismatches.
* 4,381 batch timeouts.
<!-- END jsc r2h triage -->
