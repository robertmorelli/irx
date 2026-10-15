# test262 candidates: JS regex bugs found by irx

One minimized repro per bug class, for every JavaScript engine irx has caught giving a wrong
answer (open, fixed and older-version bugs alike). Expected values follow the ECMAScript spec and
were cross-checked: every `===` assertion below passes in Bun 1.4 (JavaScriptCore), and each fails in the engine it names. IDs
link to the [bug ledger](../README.md#bug-ledger), which has the full notes and variants.

Not included: IRX-BOA-1 (`JSON.parse`, not regex) and IRX-XS-3 (a host artifact, not a bug).

## Syntax: patterns that must parse (or must not)

| ID | Engines | Assertion |
|---|---|---|
| IRX-XS-1 | XS | `new RegExp("[]", "v")` and `new RegExp("[^]", "v")` do not throw |
| IRX-QJS-1 | QuickJS (fixed) | `new RegExp("-", "v")` and `new RegExp("a-b", "v")` do not throw |
| IRX-QJS-2 | QuickJS | `new RegExp("[\\q{a\\-}]", "v")` and `new RegExp("[\\q{\\&}]", "v")` do not throw; `new RegExp("[\\q{a-}]", "v")` throws `SyntaxError` |
| IRX-E262-1 | engine262 | `new RegExp("[\\u{17F}--\\u{212A}]", "v")` does not throw (`\u{…}` as a set-operation operand) |

## `v` mode: class set operations and complements

| ID | Engines | Assertion |
|---|---|---|
| IRX-E262-2 | engine262 | `/^[^[^a]&&\d]$/v.test("ſ") === true`; `/^a[^A&&[a-z]]$/v.test("aa") === true` |
| IRX-E262-5 | engine262 | `/^[[a-z]&&a]$/v.test("b") === false`; `/^[[a-z]--a]$/v.test("a") === false`; `/^[\p{L}&&a]$/v.test("b") === false` |
| IRX-JSC-4 | JavaScriptCore | `/^[^[^a]k]$/v.test("a") === true`; `/^[^[^a][^b]]$/v.test("a") === false` |
| IRX-BOA-6 | Boa | `/^[s[^a]]$/iv.test("a") === false` |

## Case-insensitive matching (`i` with `u`/`v`)

| ID | Engines | Assertion |
|---|---|---|
| IRX-V8-5 | V8, SpiderMonkey | `/^[\q{k}]$/vi.test("K") === true`; `/^[\q{\u{17F}}]$/vi.test("ſ") === true`; `/^[[a-z]--\q{a}]$/vi.test("A") === false` |
| IRX-XS-2 | XS | `/^[S\u{1F600}]$/iv.test("s") === true`; `/^[^A]$/iv.test("a") === false` |
| IRX-E262-4 | engine262 | `/^.$/iv.test("a") === true`; `/^[^b]$/iv.test("a") === true`; `/^\W$/iv.test("-") === true`; and `/^\P{Lu}$/iv.test("a") === false` (the complement of the case-folded `\p{Lu}`, which holds `a`) |
| IRX-JSC-3 | JavaScriptCore | `/^\p{Ll}$/ui.test("S") === true`; `/^\p{Lu}$/ui.test("s") === true` (also with `vi`) |
| IRX-BOA-3 | Boa | `/^s$/i.test("ſ") === false` (non-Unicode `i` uses simple uppercase: ſ does not match s) |
| IRX-BOA-4 | Boa | `/^(?:\D\b)$/iv.test("K") === true` |
| V8 15.0 (fixed in 15.5) | V8 14.1–15.0 (Node, Deno) | `/^(?:(?i:)[b])$/v.test("B") === false`; `/^(?:(?-i:)[A-Z])$/iu.test("a") === true` (a modifier group's case flag must not leak into later classes) |

## Quantifiers: counted loops, empty iterations, backtracking into loops

| ID | Engines | Assertion |
|---|---|---|
| IRX-XS-10 | XS | `/(?:|a)*/.exec("a")[0] === "a"`; `/(?:a*?)*/.exec("a")[0] === "a"` (RepeatMatcher rejects an empty iteration once min is met) |
| IRX-XS-4 | XS | `/^(?:(?:a+){1}){2}$/.test("aa") === true` |
| IRX-HERMES-3 | Hermes | `/(?:(?:a+){1}){2}/.test("aa") === true`; `/^(?:(?:a{2,}){2}){2}$/.test("aaaaaaaa") === true` |
| IRX-BOA-7 | Boa | `/(?:(?:a+)+){2}/.test("aa") === true` |
| IRX-XS-8 | XS | `/(?:a|a){3}/.exec("aa") === null`; `/(?:a{2,}){3}/.exec("aaaa") === null` |
| IRX-XS-6 | XS | `/^(?:(?:aa(?:)*?){2})*$/.test("aaaaaa") === false` |
| IRX-XS-5 | XS | `/^(?:a|^){2}$/.test("a") === true`; `/^(?:a|\B){3}$/.test("aa") === true` |
| IRX-GRAAL-1 | GraalJS | `/^(?:a-(?:(?:(?:\b|\b)(?:)a)?){1,2}){2}$/.test("a-a-") === true` |
| IRX-BOA-5 | Boa | `/^(?:(?:\s(?:(?:){0,1}|a))+)+$/.test(" a") === true` |
| IRX-HERMES-1 | Hermes | `/^(?:(?:(?:\W+){1,1})*\s)$/.test(" \n") === true` |
| IRX-HERMES-2 | Hermes | `/^(?:(?:^a?)+?)$/.test("aa") === false` (no RangeError on a 2-character input) |
| IRX-XS-7 | XS | `/(?:a?)*b/.test("a") === false`; `/(?:a|)*b/.test("a") === false` (must terminate) |
| IRX-BOA-8 | Boa | `/(?:(?:a|)*)*b/.test("a") === false` (must terminate) |
| V8 15.0 (fixed in 15.5) | V8 15.0 (Deno) | `const r = /^(?:[^a][^K])*$/; r.test("xx"); r.test("xxx") === false` (native tier after a warm-up call) |

## Captures

| ID | Engines | Assertion |
|---|---|---|
| IRX-XS-9 | XS | `/(a|)*c/.exec("ac")[1] === "a"`; `/(a*)+/.exec("b")[1] === ""` |

## Anchors and the lazy-dot start optimization

| ID | Engines | Assertion |
|---|---|---|
| IRX-V8-1 | V8 | `/(?:.*?B^|a)/s.test("a") === true` |
| V8-3 | V8 | `/[^]*?a^|/.test("") === true`; `/(?:[\s\S]*?x^)?/.test("&") === true` |
| IRX-V8-2 | V8 | `/^(?:.*?a^)*$/s.test("") === true` |
| JSC-2 | JavaScriptCore (fixed) | `/p(?:^)?/.test("xp") === true`; `/p(?:^)*/.test("xp") === true` |

## Lookbehind

| ID | Engines | Assertion |
|---|---|---|
| IRX-HERMES-4 | Hermes | `/a(?<=x|^a)/.test("a") === true` |

## Surrogate pairs and astral characters (`u`/`v`)

| ID | Engines | Assertion |
|---|---|---|
| V8-2 | V8 ≤ 15.0 (fixed in Chrome 155), system JavaScriptCore (macOS 27) | `/(?<!\u{1F600})(?!\u{1F600})/u.exec("😀") === null`; `/(?<![a-z])(?![a-z])/u.exec("a😀").index === 3` (no match attempt inside a surrogate pair) |
| IRX-V8-3 | V8, system JavaScriptCore (macOS 27) | `/(?<![\s\S])(?:(?:^)*)(?![\s\S])/mu.test("😀") === false` |
| IRX-V8-4 | V8, system JavaScriptCore (macOS 27) | `/(?!.)|a^/u.exec("😀").index === 2`; `/\n|(?!^)/u.exec("😀").index === 2` |
| V8-1 | V8 14.6 (partly fixed) | `/[^a]$/u.test("😀") === true`; `/[\u{10000}-\u{10FFFF}]$/u.test("\u{115D3}") === true` |
| JSC-1 | system JavaScriptCore (macOS 27); fixed in Bun 1.4 | `/[a-z\u{110F0}-\u{110FF}]b/u.test("x\u{110F6}b") === true` |
| IRX-E262-3 | engine262 | `/\u{1F600}\B/u.exec("😀k") === null`; `/\W\b/u.exec("😀k")[0] === "😀"` |
| IRX-BOA-2 | Boa | `/^[😀]$/.test("\uD83D") === true` (without `u` the class holds two code units) |

## Match indices (`d`)

| ID | Engines | Assertion |
|---|---|---|
| IRX-XS-11 | XS | `/A/d.exec("éA").indices[0]` is `[1, 2]`; `/A/d.exec("KA").indices[0]` is `[1, 2]`; `/A/d.exec("😀A").indices[0]` is `[2, 3]` |
