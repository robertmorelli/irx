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

Smoke run: mismatches can be model gaps (semantics not yet adapted for this dialect) as well as engine bugs; see the bug ledger for confirmed ones.
<!-- END xs 1m results -->
