# Phase 2: capture groups (research notes and design)

Measured 2026-10-11 with the 22-question battery in [`capture-probes.json`](capture-probes.json)
(ASCII subjects; spans are `start,end`, `-` = unset). Same engine builds as the campaigns.

## Results: four capture semantics

| Q | pattern | subject | ES (all JS) | Perl 5.44 | PCRE family | automata (RE2/Go/Rust) | POSIX (LLVM, Tcl) |
|---|---|---|---|---|---|---|---|
| 01 | `(?:(a)\|b)+` | ab | g1 `-` | `-` | `0,1` | `0,1` | reset |
| 03 | `((a)\|b)+` | ab | g2 `-` | `-` | `0,1` | `0,1` | |
| 04 | `(?:(a)\|b){2}` | ab | `-` | `-` | `0,1` | `0,1` | |
| 05 | `(a*)*` | b | `-` | `0,0` | `0,0` | `0,0` | `-` (Tcl) |
| 07 | `(a\|)*` | a | `0,1` | `1,1` | `1,1` | `0,1` | |
| 08 | `(a?)?` | b | `-` | `0,0` | `0,0` | `0,0` | |
| 17 | `(?:(a)\|())*` | a | `0,1 -` | `- 1,1` | `0,1 1,1` | `0,1 -` | |
| 18 | `(?:(a)?b)+` | abb | `-` | `-` | `0,1` | `0,1` | |
| 19 | `(a\|ab)(c\|bcd)(d*)` | abcd | `0,1 1,4 4,4` | same | same | same | `0,2 2,3 3,4` |

Everything else in the battery (alternation unset branch, failed-path reset, lookaround
captures, lazy loops, last-iteration-wins) agreed across all non-POSIX engines:
captures made inside a *positive* lookahead/lookbehind survive; inside a *negative*
one they are unset.

Families:

* **ES** — V8 (d8, Node, Deno, Bun), QuickJS, Boa, Hermes, XS, engine262: a loop body's
  captures are cleared at the start of each iteration; empty iterations are rejected
  (span-mode rule `reject`). All JS shells support the `d` flag (`exec(...).indices`).
* **Perl ≥ 5.38** — clears captures each iteration like ES (perl5380delta: "bugs related to
  capture groups in quantified groups ... fixed": `"foobazfoobar" =~ /((foo)baz|foo(bar))+/`
  leaves `$2` undef), but empty iterations end the loop and *are recorded* (`stop`).
  Perl 5.34 still kept captures (older behaviour, RT #128215) except that a group not
  taking part in the last iteration was cleared (Q18).
* **PCRE family** — PCRE2/PHP, Python `re`, Ruby (Onigmo), Oniguruma, Java, .NET (all three
  engines), ICU, Swift Regex, nim-regex, Racket, Emacs: captures persist across iterations
  until overwritten; empty iterations end the loop and are recorded (`stop`).
* **Automata** — RE2, Go, Rust `regex`, fancy-regex: captures persist like PCRE, but an
  empty iteration after a non-empty one is not recorded (Q07, Q17). Their empty-loop rule
  was already "unmodeled" in span mode; capture checks should skip the same patterns.
* **POSIX** — LLVM Regex, Tcl: subexpression leftmost-longest (Q19), per-iteration reset,
  and Tcl's lookahead groups don't capture. Out of scope.

RE# and Vectorscan have no capture API in our hosts; out of scope.

## Bug found while researching

IRX-XS-9: XS loses the captures of the last successful iteration when a loop's next
iteration is rejected: `/(a|)*c/.exec("ac")` gives group 1 `null` (spec: `"a"`).

## Design

1. **Reference** (`ast.Matcher`): a capture array on the matcher; `group_cap`/`group_named`
   open and close through continuations, with save/restore on backtracking (copy the slots
   into the continuation frame). A dialect knob `capture_loop: enum { reset, keep }` clears
   the body's capture slots at the start of each iteration (`reset`: ES, Perl ≥ 5.38).
   Precompute each quantifier's group range. Empty-iteration handling reuses
   `empty_iteration` (`reject`/`stop`; `unmodeled` engines skip patterns with nullable
   loops, as span mode does). Positive lookarounds keep their captures, negative ones
   restore the slots.
2. **Group numbering**: hosts report groups in opening-parenthesis order. Two traps:
   * the empty-atom spelling `()` adds captures the tree doesn't have: the printer records,
     for each tree capture node, its printed group number (stored in the case next to
     `spell`); the extra `()` groups are ignored (or checked as always `-`/empty).
   * .NET numbers named groups after unnamed ones: print named groups as
     `(?<gN>…)` with N = overall capture ordinal so any host can reorder by name.
3. **Protocol**: a `capture` mode, like span mode but with K group slots (K = 6) per subject:
   `(1 + K) × 2` bytes per subject, `ff ff` = unset, `fe` + bits = failure. Same unit
   conversion as span mode. Compare only the first K tree groups.
4. **Hosts** (APIs checked): JS `exec` with the `d` flag; Perl `@-`/`@+`; PCRE ovector
   (`PCRE2_UNSET`); PHP `PREG_OFFSET_CAPTURE | PREG_UNMATCHED_AS_NULL`; Python `span(k)`;
   Ruby `MatchData#begin(k)`; Oniguruma region; Java `start(k)`; .NET `Groups` (reorder by
   name); ICU `range(at:)`; Swift `output[k].range`; Go `FindStringSubmatchIndex`;
   Rust `captures`; RE2 `Match(..., n)`; Racket `regexp-match-positions`; Emacs
   `match-beginning` (pad: unset trailing groups are dropped from `match-data`);
   nim `m.group(k)`.
5. **Findings**: `wrong_capture`, with expected/observed group spans in the manifest and
   triage report; the shrinker re-derives numbering from the tree on each candidate.
6. **Rollout**: 2a = only groups not inside any quantifier (all families agree; no new
   knobs); 2b = groups inside loops with `capture_loop` and the empty-iteration rules,
   validated per family by sweeping as in phase 1.

## Implementation status (2026-10-11)

Implemented as `capture` mode (`src/capture.zig`, `[capture]` in each `target.toml`): 28
targets. Validation sweeps (20 s each) left only known engine bugs or resource limits on
every target. Model decisions that came out of the sweeps:

* `[capture] loop`: `reset` (JS), `keep` (PCRE family, automata), `unmodeled` (Perl: 5.38+
  clears some loop captures per iteration but keeps those of a `*` that iterates zero times;
  cases with groups inside loops are skipped).
* Groups inside a loop whose body can match empty are skipped outside ES: which iteration
  records them differs from engine to engine (`(?:()|a)+?b` on "ab": Python, Ruby,
  Oniguruma, Emacs give group 1 `[0,0)`; PCRE, Java, .NET, Swift give unset; ICU finds no
  match; nim-regex reports `[1,2)`).
* `[capture] lookbehind = false` for every non-JS target: PCRE-style engines run a
  fixed-length lookbehind forward and Java tries lengths shortest-first, while JS and the
  model match right to left, so groups inside lookbehinds can differ legitimately.
* Ruby/Oniguruma: with named groups present, unnamed groups don't capture
  (`named_groups_only`); hosts report named groups by their printed number.
* Response lines scale with the mode's result width (a 512-case capture reply is 28 KB).

New bugs: IRX-PERL-3, IRX-JAVA-4 (stale or misplaced loop captures), IRX-XS-9.
