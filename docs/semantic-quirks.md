# Semantic quirks across regex engines

irx checks every engine against an exact model, so each place where engines legitimately disagree has to be written
down in that engine's dialect (`src/dialects/*.zig`). This document collects those differences by topic. Each one
was established by probing the engine and is confirmed by the startup self-check, which tests every atom and
assertion against the real engine. Where an engine's behavior is a bug rather than a design choice, the
[bug ledger](../README.md#bug-ledger) has it; the dialect follows the bug only when it would otherwise flood a
target, and that is noted here.

The engines below are named by target family. "Perl family" means Perl, PCRE1, PCRE2 (and PHP, Erlang), and Boost
unless stated otherwise.

## Strings: what one "character" is

| Unit | Engines |
|---|---|
| UTF-16 code units (`.` can consume half an astral character) | JavaScript without `u`/`v`, .NET |
| Code points | JavaScript with `u`/`v`, Perl family, Java, Python, Ruby, Oniguruma, Rust, RE2, Go, ICU, Swift (`.unicodeScalar`), Tcl, Racket, nim |
| Bytes (non-ASCII is not modelled) | LLVM `Regex`, macOS libc regex, GNU regex, MinRX, std::regex and Boost in the C locale (their pools are ASCII-only) |

Swift's default semantics match grapheme clusters; irx drives it with `.unicodeScalar` and `.simple` word
boundaries, which are the modes it models.

## `\w`, `\d`, `\s`

| Engine | `\w` | `\d` | `\s` |
|---|---|---|---|
| ECMAScript | `[A-Za-z0-9_]`, plus characters whose case fold is one of those under `iu`/`iv` (so `ſ` and the Kelvin sign) | `[0-9]` | WhiteSpace and LineTerminator, including U+FEFF |
| Perl `/u` | `\p{Word}`: letters, marks, Nd, Nl, Pc, ZWNJ, ZWJ | Nd | White_Space (VT, NEL; not U+FEFF) |
| PCRE2 10.43+ with UCP | L, N (all numbers, so `①`), Mn, Pc; no join controls | Nd | `\h` plus `\v`, whose fixed list includes U+180E |
| PCRE1 8.45 with UCP | L, N, `_` (no marks) | Nd | as PCRE2 |
| Java (`UNICODE_CHARACTER_CLASS`) | as Perl | Nd | White_Space |
| .NET | L, Mn, Nd, Pc | Nd | White_Space |
| Python `re` | `str.isalnum()` or `_` (letters and all numerics) | Nd | `str.isspace()`: White_Space plus U+001C..U+001F |
| Python `regex` module | `\p{Word}` | Nd | White_Space |
| Ruby (Onigmo) | ASCII | ASCII | `[ \t\n\v\f\r]` |
| Oniguruma (C) | `\p{Word}` without ZWNJ, ZWJ | Nd | White_Space |
| Rust `regex`, fancy-regex | `\p{Word}` | Nd | White_Space |
| RE2, Go, re2j | ASCII | ASCII | `[\t\n\f\r ]` (no VT) |
| ICU | `\p{Word}` | Nd | White_Space |
| Swift | letters, Nl, `_`, ASCII digits (not other Nd, No or marks) | any numeric (Nd, Nl, No) | White_Space |
| Tcl | L, Nd, Pc | Nd | White_Space plus U+180E, U+200B, U+2060, U+FEFF |
| Racket, nim, Vectorscan | ASCII (Racket); Perl-like (nim); L, N, `_` (Vectorscan) | | |
| Emacs | the `*scratch*` syntax table: most non-ASCII is word syntax, `_` is symbol syntax | `[0-9]` | syntax-table whitespace (`\n` is a comment ender, not whitespace) |
| ASCII variants: Perl `/a`, PCRE2 without UCP, Java without `UNICODE_CHARACTER_CLASS`, Oniguruma `*_IS_ASCII`, regex-lite, .NET ECMAScript | `[0-9A-Za-z_]` (.NET ECMAScript adds U+0130) | `[0-9]` | `[\t\n\v\f\r ]` |

nim-regex inherits Perl's classes but has no `\h`/`\v` (`\H` is a literal `H`).

In the ASCII variants these escapes are fixed sets: case-insensitivity does not close them, so under `i`,
`\w` still misses the Kelvin sign and `\W` still misses `k` (`escapes_ignore_case`).

`\h` and `\v` (Perl family, Java): PCRE2's and Java's `\h` lists include U+180E; Perl's `\h` is Unicode `Blank`,
which dropped U+180E when it stopped being a space separator in Unicode 6.3. In Ruby, `\h` is a hex digit.

## Word boundaries

`\b` normally compares "is `\w`" on both sides. The exceptions:

* **Ruby**: `\w` is ASCII but `\b` uses Unicode word characters.
* **.NET**: `\b` also counts ZWNJ and ZWJ as word characters, though `\w` does not.
* **ICU**: format characters (Cf) and Grapheme_Extend characters are transparent; `\b` never holds right before one,
  and otherwise compares with the nearest preceding character that is not ignorable.
* **Java without `UNICODE_CHARACTER_CLASS`**: a non-spacing mark counts as a word character when its run of marks
  follows a letter or digit (`Pattern.Bound.hasBaseCharacter`), which steps back one UTF-16 unit at a time, so an
  astral base character is not seen.
* **Emacs**: `\b` also holds at the string edges and between word characters of different scripts.
* **Tcl** spells word boundaries `\y` / `\Y`.
* **RE2, Go**: ASCII.

## Case-insensitive matching

| Engine | Rule |
|---|---|
| ECMAScript without `u` | `Canonicalize` maps to uppercase and never maps non-ASCII to ASCII (so `ſ` does not match `s`) |
| ECMAScript `u`/`v` | simple case folding |
| Perl | full case folding: a pattern `ß` (literal, or listed in a class but not in a range) matches `ss`, `SS`, `ſs`; `/aa` turns this off between ASCII and non-ASCII |
| ICU | full case folding for literals (`ß` matches `ss`, `ſS`); class members fold simply |
| PCRE family, Boost | simple case folding only (`ß` matches `ẞ`, never `ss`) |
| Perl `/aa` | no case-insensitive match between ASCII and non-ASCII (`k` vs the Kelvin sign, `s` vs `ſ`) |
| Java | `lower(upper(c))` on both sides; a literal without simple case mappings (`ß`) compiles as an exact match, so `ß` fails to match `ẞ` while `ẞ` matches `ß` (IRX-JAVA-1) |
| .NET | single-scalar lowercase mappings |
| Python `re` | simple lowercase plus sre's fixed equivalence groups (`i`/`ı`, `s`/`ſ`, `µ`/`μ`, Greek symbol variants) |
| Python `regex` | the same groups, but `ı` matches `I` and `İ` matches `i` while `ı` does not match `İ`: not an equivalence, so `ı` and `İ` are kept out of that target's pool |
| Ruby, Oniguruma | full folding, including multi-character folds inside classes (`[ß]` matches `"ss"`) |
| Rust, RE2, Go | simple case folding |
| regex-lite, Boost, std::regex, LLVM, libc | ASCII only (C locale) |
| Swift | an ASCII class member matches only ASCII subjects; others match when single-scalar lowercase mappings agree, after mapping U+1FD3 and U+1FE3 to their canonical equivalents U+0390 and U+03B0. A range reaching past ASCII also takes an uppercase letter's lowercase and a lowercase letter's uppercase (`ϑ` is in `[Θ]`, `Θ` is not in `[ϑ]`, titlecase `ǅ` is not in `[Ǆ]`); range bounds that NFC would change are rejected (IRX-SWIFT-7) |
| Tcl, Racket | a pattern character matches exactly `{p, upper(p), lower(p)}` (Racket adds `foldcase(p)`; Tcl's uppercase table adds `ß` → `ẞ`); asymmetric |
| Emacs | `case-fold-search` canonicalizes both sides (`ς Σ` → `σ`, `ẞ` → `ß`, but `ſ` and the Kelvin sign stay distinct) |
| nim | ranges accept everything between the endpoints' upper forms and between their lower forms (IRX-NIM-1, followed by the model) |

### Unicode properties under `i` (`prop_case`)

* **equivalence** (ECMAScript): a character matches `\p{Lu}` if any case-equivalent does; `\P{…}` is complemented
  before folding.
* **equivalence, complemented after folding** (Java, ICU, Rust, RE2, Go, Onigmo): `\P{Lu}` under `i` is the
  complement of the folded `\p{Lu}`.
* **cased letters** (Perl, PCRE2, .NET, Python `regex`): `\p{Lu}` and `\p{Ll}` both mean any cased letter (Lu, Ll,
  Lt).
* **plain** (Oniguruma, Vectorscan, nim, PCRE1): `i` does not reach properties.
* `v`-mode class strings: ES folds `\q{…}` strings like any other class operand, so `/[\q{k}]/vi` matches `K`.
  Irregexp (V8, SpiderMonkey) folds the string but not the subject, so only already-folded subjects match
  (IRX-V8-5). System JavaScriptCore on macOS 27 ignores `i` for `\p{…}` altogether (IRX-JSC-3).
* Ruby and Oniguruma also apply multi-character folds to properties (`\p{L}` under `i` matches `"ss"` via `ß`), so
  no `\p` is generated under `i` there.

## Line terminators, `.`, `^`, `$`

| Engine | Line terminators | `$` without `m` | Notes |
|---|---|---|---|
| ECMAScript | `\n \r` LS PS | end only | |
| Perl family, Python, Java, .NET, ICU | Perl/PCRE/Python/.NET: `\n`; Java: `\n \r \r\n` NEL LS PS; ICU: `\n` VT FF `\r` NEL LS PS | end, or before a final terminator | `(?m)^` does not match after a trailing newline at the very end (Perl, PCRE, Java, ICU) |
| Rust | `\n` | end only | `(?m)^` does match after a trailing `\n` |
| RE2, Go, nim | `\n` | end only | |
| Ruby, Oniguruma (Ruby syntax), Emacs | `\n` | `^`/`$` are always line anchors; Ruby's `m` is dotall | |
| Oniguruma Perl/Java/Python syntax | `\n` | end or before a final `\n` | start single-line; `m` sets `NEGATE_SINGLELINE` |
| Boost | `\n` FF `\r` NEL LS PS (not VT) | end only (`no_mod_m`) | under `m`, `\r\n` is one break and `^` matches after a trailing separator |
| LLVM, libc | `\n` | | without `m`, `.` matches `\n`; with `m` (REG_NEWLINE) neither `.` nor a negated class matches `\n` |
| Tcl | `\n` | | without `s` (`-linestop`) no negated class or escape matches `\n` |
| Racket | `\n` | end only | without `m`, `.` matches everything; `[^…]` always matches `\n` |
| std::regex | | | under `multiline`, `^` fails after a newline consumed earlier in the same attempt when it started at 0 (IRX-LIBCXX-1) |

`\r\n` is atomic for `^`/`$` in Java, ICU and Boost: neither matches between the two characters.

## Loops whose body matches empty

The ECMAScript rule rejects an iteration that matched empty once the minimum is met and tries the next
alternative. Perl, PCRE, Python, Java, .NET, Ruby, ICU, Swift, Racket and Emacs instead accept the empty iteration
and leave the loop. Rust's engines follow their Thompson NFA: regex-automata compiles a star over a nullable body
as `(e+)?`, `e{n,}` as `e{n-1}e+` and unrolls bounded repeats, and its searches never revisit a (state,
position) pair. So an empty first iteration ends the loop as in Perl (`(?:|a)*` on `"aa"` is `[0,0)`), but a later
empty iteration is dropped and the next alternative tried (`(?:\B|x)*` on `"ϑё"` is `[0,2)`, Perl `[0,1)`); irx
models this exactly with a regex-automata-shaped NFA (`empty_iteration = thompson`, `src/thompson.zig`).
fancy-regex hands patterns without lookarounds, backreferences, atomic groups or `\b`/`\B` to the regex crate;
its own VM stops unbounded loops like Perl and unrolls bounded ones, and it still delegates plain subexpressions
inside such a pattern (not modelled). RE2, Go, .NET NonBacktracking and libc++ have their own rules; irx does not
model them, so span and capture checks skip patterns with a nullable loop there (`empty_iteration = unmodeled`),
and mutation mode avoids them. Onigmo additionally ends a counted loop at an empty iteration before its minimum
(`(?:a+|\B){2}` on `"ba"` is `[1,1)`), a known gap in the model.

Some engines reject such bodies outright: fancy-regex and Racket refuse quantifiers (other than `?`) over a body
that can match empty; Oniguruma rejects a quantified bare assertion (`(?:\b)*`); Swift can loop forever on them
(IRX-SWIFT-4), so its target allows nullable bodies only under `?`.

## Captures in loops

Cleared at the start of each iteration in ECMAScript; kept until overwritten in the PCRE family and the automata
engines; Perl 5.38+ follows neither consistently and is not modelled. Details: [phase2-captures.md](phase2-captures.md).

## Lookbehind

| Engine | Rule |
|---|---|
| ECMAScript, .NET, Python `regex` | any length, matched right to left |
| Perl | length cap (255; irx keeps lookbehinds short) |
| PCRE2 10.43+ | variable length allowed |
| PCRE1, Python `re`, fancy-regex, Ruby, Oniguruma | fixed length per top-level branch; PCRE1 also rejects any variable quantifier inside, even `()?` |
| Boost | fixed length, and no quantifier at all, not even `{1}` |
| Java | bounded; rejects unbounded quantifiers over non-atoms, lazy unbounded ones, and counted ones over a group holding an alternation or quantifier |
| ICU | bounded; no `??`, `*?`, `+?`; no unbounded quantifier even inside a nested lookahead (irx keeps lookarounds out of ICU lookbehinds) |
| Onigmo, Oniguruma | no lookarounds or quantified captures inside, no captures in a negative lookbehind, and no atom under `i` that could match a multi-character fold; in Oniguruma's Perl, Java and Python syntaxes also no `$` (there it means end or before a final newline) |
| Racket | bounded |
| RE2, Go, Rust, Vectorscan, LLVM, libc, std::regex | no lookbehind (std::regex has no lookbehind at all) |

## Atomic groups, possessive quantifiers, backreferences

| Engine | Atomic `(?>…)` | Possessive | Backreferences |
|---|---|---|---|
| ECMAScript, std::regex | no | no | yes; a reference to a group that has not matched matches empty (libc++ fails it instead: IRX-LIBCXX-4) |
| Perl family, Java, ICU, Python 3.11+ | yes | yes, including `{m,n}+` | yes; unset group fails |
| .NET | yes | no | yes |
| Ruby, Oniguruma | yes | `*+ ++ ?+` only; `x{2,3}+` is `{2,3}` followed by `+`; none in Oniguruma's Python syntax, where `a*+` is a repeated `a*` (IRX-ONIG-2) | yes; in Ruby syntax, with any named group present, unnamed groups do not capture and references must be by name (`\k<name>`); Oniguruma's Perl, Java and Python syntaxes number groups and references normally |
| Swift | yes | no (`x*+` reads as a quantifier then `+`) | yes |
| fancy-regex | yes | no | yes; a numbered reference to a named group is a syntax error |
| Rust `regex`, RE2, Go, nim, Vectorscan | no | no | no |

Boost rejects an empty atomic group `(?>)`. A backreference compares case-insensitively under `i`.

## Start offsets and sticky matching

With a start offset, `^` keeps meaning the real string start and lookbehind sees the text before the offset in
ECMAScript (`lastIndex`), PCRE2, PHP, Perl (`pos`), Python (`search(s, pos)`), Java (`find(int)`), .NET
(`Match(s, start)`), Ruby, Oniguruma, Rust (`find_at`), RE2, ICU's C API (`uregex_find`) and nim. Tcl (`-start`)
and ICU through `NSRegularExpression` treat the offset as the start of the string. Go, Vectorscan, LLVM, libc,
Swift Regex, Emacs and RE# have no such API.

Native anchored-at-offset searches: JavaScript `y`, Perl `\G`, Python `match(s, pos)`, Java `region` + `lookingAt`,
PCRE2 `ANCHORED`, PHP `A`, `onig_match`, Ruby and .NET `\G`, RE2 `ANCHOR_START`, regex-automata
`Anchored::Yes`, ICU `uregex_lookingAt`. (Emulating sticky from the offset search would only repeat the offset
check.)

## Global search: continuing after an empty match

ECMAScript's `matchAll` continues one position after an empty match (a whole surrogate pair under `u`/`v`), and
may report an empty match where the previous match ended (`a*` on `"baa"`: `[0,0) [1,3) [3,3)`). Rust's
`find_iter` skips an empty match where the last match ended and searches one character on (`[0,0) [1,3)`); irx
models both (`global_empty_after_match`). Perl, PCRE and Python retry at the same position demanding a non-empty
match; Java and .NET advance one unit (not modelled).

## Match selection

First match in backtracking priority order everywhere except the POSIX engines (LLVM, libc, GNU regex, MinRX,
Tcl, RE#, and RE2/Go in longest mode), which take the leftmost match and then the longest at that start. macOS
libc sometimes misses the leftmost start (IRX-LIBC-2).

## Syntax spellings

* **Named groups**: `(?<name>…)` in ECMAScript, .NET, Java, Ruby, Perl family; `(?P<name>…)` in Python, nim and
  Oniguruma's Python syntax; none in std::regex, Tcl, RE#, Oniguruma Perl/Java syntax. ES2025 allows the same name
  in different alternatives; Hermes rejects it.
* **Inline flags**: scoped `(?i:…)` broadly; Ruby spells dotall `m` and has no scoped multiline; Racket has only
  `(?i:)`; QuickJS (Homebrew), Hermes and XS have no ES2025 modifiers; .NET ECMAScript and std::regex have none.
* **Extended mode** `(?x:…)`: Java and Rust also ignore whitespace inside character classes, Perl and .NET do not,
  so irx escapes every space and `#` as `\x{H}`, and hosts that rewrite `\x{H}` emit the engine's own escape.
* **Code point escapes**: `\x{H}` (Perl family, Java, Rust, ICU, Onigmo, Boost); `\u{H}` (ECMAScript with `u`);
  `\uXXXX`; Python `\U0000HHHH`; Oniguruma's Java and Python syntaxes misread `\x{H}` (Java syntax takes `\x{61}`
  as something other than `a`), so that host writes `\uHHHH`.
* **Full match wrappers**: hosts use `\A(?:…)\z`; Oniguruma's Python syntax has no `\z` (its `\Z` is the absolute
  end).
* **Class strings** `[\q{ab|c}]` (ES `v`): inside the braces the class-set syntax characters `( ) [ ] { } / - \ |`
  must be escaped, and the reserved punctuators may be (`\-`, `\&`). QuickJS rejects those escapes and accepts a
  bare `-` (IRX-QJS-2); GraalJS also accepts a bare `-`.
* **Empty branches**: POSIX ERE rejects `(|a)` and `a|`; nim rejects `(?<=)`, `(?=)`.
* **Counted repeats**: nim and fancy-regex cap big bounds at 100 (`{0,254}` is rejected or too large to compile).

## Oniguruma's syntax modes

Oniguruma can parse patterns as Ruby, Perl, Java or Python would. The modes change more than spelling:

* Ruby's capture rules (unnamed groups stop capturing once a named group exists; references by name only) apply
  only in Ruby syntax.
* `$` without `m` means end or before a final newline in the Perl, Java and Python syntaxes, and Oniguruma then
  rejects it inside lookbehind.
* `\X` is a grapheme cluster only in the Ruby and Perl syntaxes.
* The Python syntax accepts atomic groups but not possessive quantifiers, though Python 3.11 added both: `a*+` parses
  silently as a repeated `a*`, so `a*+a` matches `"a"` where CPython does not (IRX-ONIG-2).
* The Java and Python syntaxes misread `\x{H}` (see code point escapes above), and the Python syntax has no `\z`.

## Library-specific limits worth knowing

* Rust's `regex` size limit (10 MB by default; irx raises it to 64 MB) and fancy-regex's delegate NFA limit reject
  big counts over large Unicode classes next to `\b`.
* Dense DFAs (regex-automata) take tens of milliseconds to build per pattern.
* .NET `RegexOptions.Compiled` on .NET 9 crashes code generation for a lazy loop inside a lookbehind
  (IRX-DOTNET-2, fixed in .NET 11).
* gawk's copy of GNU regex handles `REG_ICASE` its own way (`[a-c]` matches `"A"` but not `"a"`) and treats some
  anchors unexpectedly; neither has been checked against glibc itself.
* re2j's Unicode tables are old (U+180E is still `Zs`, U+1F600 has no category).

## `\X`, extended grapheme clusters

Perl, ICU, Java, Ruby (Onigmo) and Python's `regex` module follow UAX #29 including GB9c (a Devanagari consonant,
virama, consonant sequence is one cluster); Oniguruma 6.9 and PCRE2 10.49 lack GB9c. Every engine starts the cluster at the current
position without looking behind it and matches it atomically. PCRE2 breaks between a Prepend character and an
emoji (IRX-PCRE2-6). Boost's `\X` is a character plus following combining marks (`\r\n` is two), and fails after an optional or
repeated element (IRX-BOOST-3). PCRE1's
grapheme data predates Unicode 11 (emoji modifiers were their own class). JavaScript, .NET, Rust, RE2, Go and the
POSIX engines have no `\X`, and neither do Oniguruma's Java and Python syntaxes (only its Ruby and Perl syntaxes).
