# XS (Moddable, jsvu)

See [`target.toml`](target.toml) for how irx drives this engine; run it with `tools/irx_target.py xs`.
Bugs found here are listed in the [bug ledger](../../README.md#bug-ledger).

<!-- BEGIN xs results -->
## XS campaign results

10-minute campaign, 8 cores, modes `shell` + `shell-repeat`, edit-distance-5 A/R pairs, via `tools/bridge.py`.

* 758,880 patterns over 9 tables.
* 200 self-check `SyntaxError`s: IRX-XS-1 (empty `v` classes).
* 248 wrong results: IRX-XS-2 (`v` classes ignore `i`), e.g. `/^[S\u{1F600}]$/iv` misses `"s"`.
* 780 aborted batches: IRX-XS-3 (`RangeError: buffer overflow`, sequence-dependent).
* 2,178 timeouts (not triaged).

Counts are distinct findings; one bug produces many distinct regexes. Shapes were checked on the minimized subset triaged during the campaign, and representatives were confirmed against d8 15.5 and the relation model.
<!-- END xs results -->

<!-- BEGIN xs notes -->
## XS (Moddable) results

Engine: XS from jsvu (`vendor/jsvu-home/.jsvu/bin/xs`), driven through `tools/bridge.py`
(`--shell "python3 tools/bridge.py …/xs {driver} {mode}"`).

### XS bug 1: empty classes rejected under the `v` flag

```js
new RegExp("[]",  "v")   // XS: SyntaxError   (d8 15.5, QuickJS: accepted)
new RegExp("[^]", "v")   // XS: SyntaxError   (d8 15.5, QuickJS: accepted)
```

ES2024 allows empty `ClassContents` in UnicodeSets mode, so `/[]/v` (matches nothing) and `/[^]/v`
(matches any character) are valid. XS accepts both without `v` and accepts non-empty `v` classes such as
`[a]` and `[^a]`. Found by the startup atom self-check, whose assertion probes use `[^]{i}…[^]*`: all 200
`v`-flag probes came back as `SyntaxError`. This is a conformance (valid syntax rejected) bug, not a wrong
match. Not reported upstream.
<!-- END xs notes -->

<!-- BEGIN xs 1m results -->
### xs: 1-minute smoke campaign

* 109,216 patterns, 3 tables, 426 distinct findings; self-check 1,628,352 probes, 76,472 mismatches, 0 engine failures
* findings by kind: 224 crash (batch), 202 timeout (batch), 200 syntax_error (selfcheck)

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END xs 1m results -->

<!-- BEGIN xs 10m results -->
### XS (Moddable, jsvu): 10m campaign

* 801,536 patterns, 10 tables, 3,126 distinct findings; self-check 1,628,352 probes, 76,472 mismatches, 0 engine failures
* findings by kind: 2,172 timeout (batch), 952 crash (batch), 200 syntax_error (selfcheck), 2 wrong_result

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 2 | wrong_result | `` | `"a"` | `" "` | `(?:a\|^){2}` | 00 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END xs 10m results -->

<!-- BEGIN xs 10m triage -->
### xs: 10-minute campaign triage

* New (some from the campaign, the rest from the cross-check): **IRX-XS-5** (`(?:a|^){2}` misses `"a"`, the
  campaign's only minimized wrong result), **IRX-XS-4**, **IRX-XS-6**, **IRX-XS-7** (hang on `(?:a?)*b` vs `"a"`).
* The 76,472 self-check mismatches are IRX-XS-1 (`[^]` rejected in `v` mode, so every `[^]*`-wrapped assertion probe
  fails) and IRX-XS-2 (`v`-mode classes ignore `i`). The 200 syntax errors are IRX-XS-1.
* The 952 crashes are IRX-XS-3 (`RangeError: buffer overflow`, uncatchable). The 2,172 timeouts are probably
  IRX-XS-7 hangs, which is why only part of the 0.8 M cases executed.
<!-- END xs 10m triage -->

<!-- BEGIN xs 5m results -->
### XS (Moddable, jsvu): 5m campaign

* 270,144 patterns, 4 tables, 3,892 distinct findings; self-check 1,628,352 probes, 76,472 mismatches, 0 engine failures
* findings by kind: 2,367 wrong_span, 819 crash (batch), 706 timeout (batch), 200 syntax_error (selfcheck)

Most common minimized shapes (kind, flags, A, R, pattern, observed bits):

| n | kind | flags | A | R | pattern | bits |
|---|---|---|---|---|---|---|
| 3 | wrong_span | `` | `"aaaaaa"` | `"aaaa"` | `(?:a{2,}){3}` | 02 |
| 3 | wrong_span | `` | `"a"` | `"aK"` | `(?:\|a)*` | 02 |
| 2 | wrong_span | `` | `"aaaaaa"` | `"aaaa"` | `(?:a{2,3}){3}` | 02 |
| 2 | wrong_span | `` | `"a"` | `"aK"` | `(?:a??){0,}` | 02 |
| 2 | wrong_span | `` | `"a"` | `"aK"` | `(?:a*?)+` | 02 |
| 2 | wrong_span | `` | `"aaaaaa"` | `"aaaa"` | `(?:a{2,}?){3,3}` | 03 |
| 2 | wrong_span | `` | `"a"` | `"aK"` | `(?:a*?)*` | 02 |
| 2 | wrong_span | `` | `"aaa"` | `"aa"` | `(?:a\|a){3,}` | 03 |

Unreviewed counts: a mismatch is an engine bug or a model gap until triaged; confirmed bugs are in the bug ledger, and the triage notes below say which findings are which.
<!-- END xs 5m results -->
